# Initialize Workflow

This workflow is used to initialize the environment for the other workflows. It can be used to set up any necessary resources, such as databases, storage accounts, or other services that are required for the other workflows to run.

As part of initialization, it cleans up leftover build folders before the build, in case a previous run left non-expected files behind. The following folders under `$ENV:PIPELINE_WORKSPACE\App` are removed if they exist:

- `.buildpackages`
- `.buildartifacts\Dependencies`
- `.buildartifacts\TestApps`
- `.buildartifacts\Apps`
- `.output`

## INPUT Parameters

No parameters.

## ENV INPUT variables

No environment input parameters.

## ENV OUTPUT variables

No environment output parameters.
