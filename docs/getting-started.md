# Getting started

## Set up ecs-conex in your AWS account

This only needs to be performed once per account. More instruction and scripts coming soon.

## Have ecs-conex watch a GitHub repository

Once ecs-conex is running in your AWS account, you can ask it to build a Docker image each time you push changes to a GitHub repository.

1. Setup the GitHub repository. You will need a `Dockerfile` at the root level of the repository.
2. Your ecs-conex CloudFormation stack was provided with a GitHub access token. Make sure that the GitHub user corresponding to that token is listed as a collaborator and has permission to read from your GitHub repository.
3. Clone the ecs-conex repository locally, giving you access to the `watch.sh` script in the `scripts` folder.
4. Make sure you have awscli installed.
5. Clone your Github repository locally, and use the `watch.sh` script to register the Github repository with ecs-conex.

In this example, we assume:
- that a ecs-conex stack has already been created in `us-east-1` called `ecs-conex-production`,
- a new GitHub repository called `my-github-repo` is already created,
- you have generated a personal GitHub access token `abcdefghi` with `admin:repo_hook` and `repo` scopes, and
- awscli is installed and properly configured.

```sh
$ git clone https://github.com/mapbox/ecs-conex
$ mkdir my-github-repo
$ cd my-github-repo
$ git init
$ git remote add origin git@github.com:my-username/my-github-repo
$ echo "FROM ubuntu" > Dockerfile
$ git commit -am "my first commit"
$ git push --set-upstream origin master
$ GithubAccessToken=abcdefghi ../ecs-conex/scripts/watch.sh us-east-1:ecs-conex-production
```

You can check to see if your repository is being watched by looking at Settings > Webhooks & Services for your repository:

```
https://github.com/my-username/my-github-repo/settings/hooks
```

## Registry maintenance

ecs-conex will automatically delete the oldest images in your registry to maintain a maximum image count of 900. It will only delete images with an imageTag that resemble a GitSha. Any image with a 40 hexadecimal-character imageTag will be subject to deletion.
