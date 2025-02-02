
# BCDevOps Flows for Microsoft Dynamics 365 Business Central

<span style="color:red">The project is still in development. Please contact me if you want to contribute to this project. !!! UNTIL FIRST STABLE VERSION BREAKING CHANGES CAN HAPPEN WITHOUT ANY ANNOUNCEMENT !!! There won't be any change log or manuals available until the first stable version is released.</span>

## How to start

This section describes most important points how to use and configure BCDevOps Flows.

1. [Create a fork/clone of this repository](.Scenarios/HowToStart/ForkRepository.md)
1. [Connect Azure DevOps with your fork/clone](.Scenarios/HowToStart/ConnectAzureDevOpsWithGitHub.md)

## Supported pipeline steps
We strongly recommend to not change any of the standard pipeline or standard scripts. It's highly likely that customized scripts and/or pipelines will be broken in a future update.

You can use the following documentation of supported scripts to build your own pipelines (yaml).

- [WorkflowInitialize](./WorkflowInitialize/README.md)
- [ReadSettings](./ReadSettings/README.md)
- [DetermineArtifactUrl](./DetermineArtifactUrl/README.md)
- [RunPipeline](./RunPipeline/README.md)
- [StoreAppLocally](./StoreAppLocally/README.md)
- [DeployToCloud](./DeployToCloud/README.md)
- [PipelineCleanup](./PipelineCleanup/README.md)

## Obsoletion

<span style="color:red">This section describes future process. This IS NOT YET FOLLOWED and will be active once the project is in stable version.</span>

We will try to not introduce any breaking changes without announcement. However, as the solution depends on external libraries (such as BCContainerHelper) we can not guarantee that there will not be breaking changes caused by other libraries.

For breaking changes not caused by third party libraries, we will announce any such change at least 6 months in advance. We reserve rights to short or even remove this period for any reason.
