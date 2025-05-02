
# BCDevOps Flows for Microsoft Dynamics 365 Business Central

<span style="color:red">The project is still in development. Please contact me if you want to contribute to this project. !!! UNTIL FIRST STABLE VERSION BREAKING CHANGES CAN HAPPEN WITHOUT ANY ANNOUNCEMENT !!! There won't be any change log or manuals available until the first stable version is released.</span>

## How to start

This section describes most important points how to use and configure BCDevOps Flows.

1. [Create Azure DevOps Agent Pool and at least one self-hosted Agent](.Scenarios/HowToStart/ConfigureAgentPool.md)
1. [Create a fork/clone of this repository](.Scenarios/HowToStart/ForkRepository.md)
1. [Connect Azure DevOps with your fork/clone](.Scenarios/HowToStart/ConnectAzureDevOpsWithGitHub.md)
1. [Configure Azure DevOps variables](.Scenarios/HowToStart/ConfigAzureDevOpsVariables.md)

## Create your first project

This section describes how to start using BCDevOps Flows.
1. [Create New BCDevOps Flows Project](.Scenarios/CreateNewProject.md)
1. [Add BCDevOps Flows to Existing Project](.Scenarios/AddBCDevOpsFlowsToExistingProject.md)
1. [Configure Pipelines](.Scenarios/ConfigurePipelines.md)

## Permissions & Security overview

This section describes all important security/permission settings.
1. [Build Service Permissions (Project Level)](.Scenarios/Permissions/BuildServicePermissions.md)
1. All pipelines must have access to configured Agent Pool
1. All pipelines must have access to configured Variable Group

## Important/Interesting setting

The list of supported configuration is available in [Settings Overview](.Scenarios/SettingsOverview.md). Below is a list of the most important setting you should know about or that is different from AL-Go.

- [country](/.Scenarios/SettingsOverview.md#country)
- [artifact](/.Scenarios/SettingsOverview.md#artifact)
- [versioningStrategy](/.Scenarios/SettingsOverview.md#versioningStrategy)
- [writableFolderPath](/.Scenarios/SettingsOverview.md#writableFolderPath)
- [artifactUrlCacheKeepHours](/.Scenarios/SettingsOverview.md#artifactUrlCacheKeepHours)
- [preprocessorSymbols](/.Scenarios/SettingsOverview.md#preprocessorSymbols)
- [removeInternalsVisibleTo](/.Scenarios/SettingsOverview.md#removeInternalsVisibleTo)
- [overrideResourceExposurePolicy](/.Scenarios/SettingsOverview.md#overrideResourceExposurePolicy)

## Supported pipeline steps
We strongly recommend to not change any of the standard pipeline or standard scripts. It's highly likely that customized scripts and/or pipelines will be broken in a future update.

You can use the following documentation of supported scripts to build your own pipelines (yaml).

- [WorkflowInitialize](./WorkflowInitialize/README.md)
- [SetupPipelines](./SetupPipelines/README.md)
- [InitNuget](./InitNuget/README.md)
- [ReadSettings](./ReadSettings/README.md)
- [VerifyAuthContext](./VerifyAuthContext/README.md)
- [DetermineNugetPackages](./DetermineNugetPackages/README.md)
- [DetermineArtifactUrl](./DetermineArtifactUrl/README.md)
- [IncreaseVersion](./IncreaseVersion/README.md)
- [BuildWithNuget](./BuildWithNuget/README.md)
- [RunPipeline](./RunPipeline/README.md)
- [StoreAppLocally](./StoreAppLocally/README.md)
- [PushBackToRepo](./PushBackToRepo/README.md)
- [DeployToCloud](./DeployToCloud/README.md)
- [PipelineCleanup](./PipelineCleanup/README.md)

## Obsoletion

<span style="color:red">This section describes future process. This IS NOT YET FOLLOWED and will be active once the project is in stable version.</span>

We will try to not introduce any breaking changes without announcement. However, as the solution depends on external libraries (such as BCContainerHelper) we can not guarantee that there will not be breaking changes caused by other libraries.

For breaking changes not caused by third party libraries, we will announce any such change at least 6 months in advance. We reserve rights to short or even remove this period for any reason.
