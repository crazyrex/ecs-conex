#!/usr/bin/env bash

set -eu
set -o pipefail

regions=(us-east-1 us-west-2 eu-west-1)
tmpdir="$(mktemp -d /mnt/data/XXXXXX)"

function before_image() {
  local region=$1
  echo ${AccountId}.dkr.ecr.${region}.amazonaws.com/${repo}:${before}
}

function after_image() {
  local region=$1
  local sha=${2:-${after}}
  echo ${AccountId}.dkr.ecr.${region}.amazonaws.com/${repo}:${sha}
}

function login() {
  local region=$1
  eval "$(aws ecr get-login --region ${region})"
}

function ensure_repo() {
  local region=$1
  aws ecr describe-repositories \
    --region ${region} \
    --repository-names ${repo} > /dev/null 2>&1 || create_repo ${region}
}

function create_repo() {
  local region=$1
  aws ecr create-repository --region ${region} --repository-name ${repo} > /dev/null
}

function github_status() {
  local status=$1
  local description=$2

  echo "sending ${status} status to github"

  curl -s \
    --request POST \
    --header "Content-Type: application/json" \
    --data "{\"state\":\"${status}\",\"description\":\"${description}\",\"context\":\"ecs-conex\"}" \
    ${status_url} > /dev/null
}

function parse_message() {
  ref=$(node -e "console.log(${Message}.ref);")
  after=$(node -e "console.log(${Message}.after);")
  before=$(node -e "console.log(${Message}.before);")
  repo=$(node -e "console.log(${Message}.repository.name);")
  owner=$(node -e "console.log(${Message}.repository.owner.name);")
  user=$(node -e "console.log(${Message}.pusher.name);")
  deleted=$(node -e "console.log(${Message}.deleted);")
  status_url="https://api.github.com/repos/${owner}/${repo}/statuses/${after}?access_token=${GithubAccessToken}"
}

function credentials() {
  role=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/) || :
  if [ -z "${role}" ]; then
    return
  fi

  creds=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/${role})
  accessKeyId=$(node -e "console.log(${creds}.AccessKeyId)")
  secretAccessKey=$(node -e "console.log(${creds}.SecretAccessKey)")
  sessionToken=$(node -e "console.log(${creds}.SessionToken)")

  args=""
  if grep -O "ARG AWS_ACCESS_KEY_ID" ./Dockerfile > /dev/null 2>&1; then
    [ -n "${accessKeyId}" ] && args="--build-arg AWS_ACCESS_KEY_ID=${accessKeyId} "
  fi

  if grep -O "ARG AWS_SECRET_ACCESS_KEY" ./Dockerfile > /dev/null 2>&1; then
    [ -n "${secretAccessKey}" ] && args="--build-arg AWS_ACCESS_KEY_ID=${secretAccessKey} "
  fi

  if grep -O "ARG AWS_SESSION_TOKEN" ./Dockerfile > /dev/null 2>&1; then
    [ -n "${sessionToken}" ] && args="--build-arg AWS_ACCESS_KEY_ID=${sessionToken}"
  fi

  if grep -O "ARG NPMToken" ./Dockerfile > /dev/null 2>&1; then
    [ -n "${NPMToken}" ] && args="--build-arg NPMToken=${NPMToken}"
  fi
}

function cleanup() {
  exit_code=$?

  parse_message

  if [ "${exit_code}" == "0" ]; then
    github_status "success" "ecs-conex successfully completed"
  else
    github_status "failure" "ecs-conex failed to build an image"
  fi

  rm -rf ${tmpdir}
}

function main() {
  echo "checking docker configuration"
  docker version > /dev/null

  echo "checking environment configuration"
  MessageId=${MessageId}
  Message=${Message}
  AccountId=${AccountId}
  GithubAccessToken=${GithubAccessToken}
  StackRegion=${StackRegion}
  NPMToken=${NPMToken}

  echo "parsing received message"
  parse_message

  echo "processing commit ${after} by ${user} to ${ref} of ${owner}/${repo}"
  github_status "pending" "ecs-conex is building an image"
  [ "${deleted}" == "true" ] && exit 0

  git clone https://${GithubAccessToken}@github.com/${owner}/${repo} ${tmpdir}
  cd ${tmpdir} && git checkout -q $after || exit 3

  if [ ! -f ./Dockerfile ]; then
    echo "no Dockerfile found"
    exit 0
  fi

  echo "attempt to fetch previous image ${before} from ${StackRegion}"
  ensure_repo ${StackRegion}
  login ${StackRegion}
  docker pull "$(before_image ${StackRegion})" 2> /dev/null || :

  echo "gather local credentials and setup --build-arg"
  credentials

  echo "building new image"
  docker build --quiet ${args} --tag ${repo} ${tmpdir}

  for region in "${regions[@]}"; do
    ensure_repo ${region}
    login ${region}

    echo "pushing ${after} to ${region}"
    docker tag -f ${repo}:latest "$(after_image ${region})"
    docker push "$(after_image ${region})"

    if git describe --tags --exact-match 2> /dev/null; then
      tag="$(git describe --tags --exact-match)"
      echo "pushing ${tag} to ${region}"
      docker tag -f ${repo}:latest "$(after_image ${region} ${tag})"
      docker push "$(after_image ${region} ${tag})"
    fi
  done

  echo "completed successfully"
}

trap "cleanup" EXIT
main 2>&1 | FASTLOG_PREFIX='[${timestamp}] [ecs-conex] '[${MessageId}] fastlog info
