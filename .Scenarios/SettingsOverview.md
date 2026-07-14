# BCDevOps Flows Settings Overview

This page explains the configuration parameters supported by BCDevOps Flows.

## Where are the settings located

Settings can be defined in Azure Devops variables or in various settings file. When running a workflow or a local script, the settings are applied by reading settings from Azure DevOps variables and one or more settings files. Last applied settings file wins. The following lists the order of locations to search for settings:

1. You can use `External settings JSON file` that will be used for all projects and repositories. Azure DevOps does not have **Organization Setup** so this is the only option how to replicate Organization Setup from GitHub. The link can be http or https.
1. `AL_PROJECTSETTINGS` is **Azure DevOps environment variable** for project setting

1. `.azure-pipelines/BCDevOpsFlows.Settings.json` is the **repository settings file**. This settings file contains settings that are relevant for all projects in the repository.

1. `.azure-pipelines/\<pipelineName\>.settings.json` is the **workflow-specific settings file**. This option is used for the Current, NextMinor and NextMajor workflows to determine artifacts and build numbers when running these workflows.
    - \<pipelineName\> is specified in AL_PIPELINENAME environment variable
    - If this environment variable is not found, the predefined Azure DevOps variable (Build.DefinitionName) is used instead.

1. `.azure-pipelines/\<userReqForEmail\>.settings.json` is the **user-specific settings file**. This option is rarely used, but if you have special settings, which should only be used for one specific user (potentially in the local scripts), these settings can be added to a settings file with the email of the user followed by `.settings.json` (example: Tom@bccaptain.com.au.Settings.json)

## BC DevOps Flows pipeline setup

The following setup is designed to automate management of your pipelines.

### IMPORTANT: Only specific setting files are supported
This setup can be placed only in **External settings json file**, **BCDevOpsFlows.Settings.json** or **\<pipelineName\>.settings.json** (both the pipeline itself or the SetupPipelines.settings.json). All other (Azure DevOps variable and user-specific) settings are ignored.

### **IMPORTANT - obsoleted settings, will be removed in the future** 
| Name | Description | Details |
| :-- | :-- | :-- |
| <a id="BCDevOpsFlowsVariableGroup"></a>BCDevOpsFlowsVariableGroup | Specifies name of the variable group in your Azure DevOps pipeline that hosts environment variables. Once pipelines are created for the first time, you must allow access to the Pool in Azure DevOps. | Replaced by BCDevOpsFlowsVariableGroups array to support multiple variable groups. This option will be removed 2026/07. |
| <a id="enableLinterCop"></a>enableLinterCop | If enableLinterCop is set to true, the workflow will enable the LinterCop analyzer when building. LinterCop is community-driven cop. You can read more information in official repository [LinterCop at GitHub](https://github.com/StefanMaron/BusinessCentral.LinterCop). | Replaced by ALCops. Use ALCops analyzers instead (e.g. enableALCopsLinterCop). See [LinterCop Migration](https://alcops.dev/docs/lintercop-migration/). This option will be removed 2026/07. |

### **IMPORTANT - run SetupPipelines pipeline to apply this settings** 
This setup is not applied until you run the **SetupPipelines** pipeline. **SetupPipelines** pipeline must be created manually and must be run whenever any of the following settings is changed.

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="pipelineBranch"></a>pipelineBranch | Specify what branch should be used in Azure DevOps to run pipelines from. | main |
| <a id="pipelineFolderStructure"></a>pipelineFolderStructure | Specifies the parent folder for pipelines in Azure DevOps. This settings is not a folder in repository, but folder in Azure DevOps Pipelines (Project -> Pipelines -> All -> folders). Allowed values: "Repository" - repository name is used as folder, "Pipeline" - pipeline name is used as folder, "Path" - manually specified path in "pipelineFolderPath" property (see below) | Repository |
| <a id="pipelineFolderPath"></a>pipelineFolderPath | Specifies the folder path in Azure DevOps pipelines. Only applicable when pipelineFolderStructure is set to Path. Leave blank and set pipelineFolderStructure to Path if you do not want to use folders. |  |
| <a id="pipelineSkipFirstRun"></a>pipelineSkipFirstRun | When a new pipeline is created in Azure DevOps, it's automatically run to test the setup and permissions. We recommend to always run the pipeline after it is created to verify setup and permissions. | $false |
| <a id="pipelineSelfHealing"></a>pipelineSelfHealing | When enabled, every pipeline run (except pull request builds and runs on branches other than **pipelineBranch**) checks whether the pipeline YAML files (including their templates) match the current settings and, if they drifted, commits and pushes the corrected files back to the repository. This applies settings changes (variable groups, triggers, schedules, pool names, [pipelineYamlPatches](#pipelineYamlPatches), ...) on the next run without re-running the SetupPipelines pipeline. Structural changes (new pipelines, renamed pipelines, pipeline folder changes in Azure DevOps) still require SetupPipelines. The commit is pushed with `[skip azurepipelines]` so it does not trigger new runs. | $false |
| <a id="pipelineYamlPatches"></a>pipelineYamlPatches | Specifies additional properties to set in (or remove from) the pipeline YAML files, applied by both the SetupPipelines pipeline and self-healing (see [pipelineSelfHealing](#pipelineSelfHealing)). Each entry is a structure with **path** (dot-separated YAML path, array elements addressed as `name[0]`), either **value** or **remove** = true, and an optional **pipeline** name filter (wildcards supported, default `*`). Patches are never applied to the SetupPipelines pipeline itself. See example below. | [ ] |
| <a id="BCDevOpsFlowsPoolName"></a>BCDevOpsFlowsPoolName | Name of the Azure DevOps Pool that hosts your self-hosted agents. The project must have access to the pool. Once pipelines are created for the first time, you must allow access to the Pool in Azure DevOps. | SelfHostedWindows |
| <a id="BCDevOpsFlowsPoolNameCICD"></a>BCDevOpsFlowsPoolNameCICD | Name of the Azure DevOps Pool that hosts your self-hosted agents. This agent pool is used for CICD pipeline. If blank/not specified, the value from **BCDevOpsFlowsPoolName** is used instead. You can use different Agent Pool to have different pool approvals and check (e.g. business hours). See Microsoft Learn for more details https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals?view=azure-devops&tabs=check-pass |  |
| <a id="BCDevOpsFlowsPoolNamePublishToProd"></a>BCDevOpsFlowsPoolNamePublishToProd | Name of the Azure DevOps Pool that hosts your self-hosted agents. This agent pool is used for PublishToProduction pipeline. If blank/not specified, the value from **BCDevOpsFlowsPoolName** is used instead. You can use different Agent Pool to have different pool approvals and check (e.g. business hours). See Microsoft Learn for more details https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals?view=azure-devops&tabs=check-pass |  |
| <a id="BCDevOpsFlowsResourceRepositoryName"></a>BCDevOpsFlowsResourceRepositoryName | Specifies name of the GitHub repository where you host your version of BCDevOpsFlows (format "owner/repositoryname") |  |
| <a id="BCDevOpsFlowsResourceRepositoryBranch"></a>BCDevOpsFlowsResourceRepositoryBranch | Specifies what branch from your GitHub BCDevOpsFlows repository you want to use. | main |
| <a id="BCDevOpsFlowsServiceConnectionName"></a>BCDevOpsFlowsServiceConnectionName | Specifies name of Azure DevOps Service Connection that is configured and allowed to access your GitHub with BCDevOpsFlows scripts. | BCDevOpsFlows |
| <a id="BCDevOpsFlowsVariableGroups"></a>BCDevOpsFlowsVariableGroups | Specifies name of the variable groups in your Azure DevOps pipeline that hosts environment variables. Once pipelines are created for the first time, you must allow access to the variable group(s) in Azure DevOps or set the group as public. | ["BCDevOpsFlows"] |
| <a id="BCDevOpsFlowsAuthContextVarName"></a>BCDevOpsFlowsAuthContextVarName | Specifies the name of environment variable where the authentication context for deployment steps is stored. | AL_AUTHCONTEXT |
| <a id="BCDevOpsFlowsTrustedNuGetFeedVarName"></a>BCDevOpsFlowsTrustedNuGetFeedVarName | Specifies the name of environment variable where the trusted NuGet feed is stored. | AL_TRUSTEDNUGETFEEDS |
| <a id="workflowTrigger"></a>workflowTrigger | Specifies pipeline change triggers. See [Azure DevOps CI trigger](https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/azure-repos-git?view=azure-devops&tabs=yaml#ci-triggers) documentation at Microsoft Learn to learn more about structure (or [GitHub CI trigger](https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/github?view=azure-devops&tabs=yaml#ci-triggers) for Hybrid Deployment). This setting is available for all pipelines except "PullRequest". | Set for CICD and PublishToProduction pipelines |
| <a id="workflowPRTrigger"></a>workflowPRTrigger | Specifies pipeline Pull Request triggers. See [Azure DevOps PR trigger](https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/azure-repos-git?view=azure-devops&tabs=yaml#pr-triggers) documentation at Microsoft Learn to learn more about setting up the PR trigger in Azure DevOps project (this cannot be specified in BCDevOpsFlows settings, any value specified in settings is ignored) or [GitHub PR trigger](https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/github?view=azure-devops&tabs=yaml#pr-triggers) for Hybrid Deployment. This setting is available ONLY for the "PullRequest" pipeline. | Set for PullRequest pipeline but respected only in Hybrid deployment |
| <a id="workflowSchedule"></a>workflowSchedule | Specifies schedule when the pipeline should be automatically run. See documentation at Microsoft Learn to learn more about structure https://learn.microsoft.com/en-us/azure/devops/pipelines/process/scheduled-triggers. This setting is available for all pipelines except "PullRequest". | Set for TestCurrent, TestNextMinor and TestNextMajor |
| <a id="updateVersionNumber"></a>updateVersionNumber | Specifies the version (relative or absolute) to what the app version should be updated to. This setting is applied only to CICD and PublishToProduction pipelines. You can use both relative (+1, +0.1, ...) or absolute (1.0, 23.5, ...) notations. You must use only values allowed by the versioningStrategy. Allowed relative changes per strategy: strategies **0** and **2** support `+1` and `+0.1`; strategy **3** additionally supports `+0.0.1`; strategy **10** supports all four (`+1`, `+0.1`, `+0.0.1`, `+0.0.0.1`). For absolute values, use `Major.Minor` for strategies 0 and 2, `Major.Minor.Build` for strategy 3, or `Major.Minor.Build.Revision` for strategy 10. |  |
| <a id="runWith"></a>runWith | Specifies the engine that is used for Build tasks in pipelines. Supported values are **BcContainerHelper** and **NuGet**. See table below for differences between the two engines. | BcContainerHelper |
| <a id="allowPrerelease"></a>allowPrerelease | Specifies whether the prerelease (preview) packages should be used as AL dependencies. | false |

#### Differences in runWith - BCContainerHelper vs. NuGet

Table below shows what functionality is currently supported in BCDevOps Flows by the engine.

|                                     | BCContainerHelper | NuGet     |
| :--                                 | :--               | :--       |
| Build an app file                   | Supported         | Supported |
| Fail the build on error             | Supported         | Supported |
| Fail the build on warning           | Supported         | Supported |
| Build with standard Cops            | Supported         | Supported |
| Build with custom Cops              | Supported         | Supported |
| Use custom RuleSets                 | Supported         | Supported |
| Use custom external RuleSets        | Supported         | Supported |
| Validate upgrade breaking changes   | Supported         | -         |
| Validate mandatory affixes          | Supported         | -         |
| Run Page Scripting                  | -                 | -         |
| Run Automated Tests                 | Supported         | -         |

#### Example of "workflowTrigger" (used as default for CICD pipeline)

```json
  "workflowTrigger": {
    "batch": true,
    "branches": {
      "include": [
        "test",
        "preview"
      ]
    },
    "paths": {
      "exclude": [
        ".azure-pipelines"
      ]
    }
  }
```

#### Example of "pipelineYamlPatches"

Disables auto cancellation of in-progress runs when the pull request is updated (pr.autoCancel) for the PullRequest pipeline and sets a job timeout for the CICD pipeline:

```json
  "pipelineYamlPatches": [
    {
      "pipeline": "PullRequest",
      "path": "pr.autoCancel",
      "value": false
    },
    {
      "pipeline": "CICD",
      "path": "jobs[0].timeoutInMinutes",
      "value": 120
    }
  ]
```

#### Example of "workflowSchedule"

```json
  "workflowSchedule": {
    "cron": "0 2 15 * *",
    "displayName": "Fifteenth of every month",
    "branches": {
      "include": [
        "main",
        "master"
      ]
    }
  }
```

## Basic Project settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="country"></a>country | Specifies which country this app is built against. | au |
| <a id="repoVersion"></a>repoVersion | RepoVersion is the project version number. The Repo Version number consists of \<major>.\<minor> only and is used for naming build artifacts in the CI/CD workflow. Build artifacts are named **\<project>-Apps-\<repoVersion>.\<build>.\<revision>** and can contain multiple apps. The Repo Version number is used as major.minor for individual apps if versioningStrategy is +16. | 1.0 |
| <a id="appFolders"></a>appFolders | appFolders should be an array of folders (relative to project root), which contains apps for this project. Apps in these folders are sorted based on dependencies and built and published in that order.<br />You can also use full paths if apps are available in a folder on the machine where the Azure DevOps agent is running. | [ ] |
| <a id="testFolders"></a>testFolders | testFolders should be an array of folders (relative to project root), which contains test apps for this project. Apps in these folders are sorted based on dependencies and built, published and tests are run in that order.<br />You can also use full paths if apps are available in a folder on the machine where the Azure DevOps agent is running. | [ ] |
| <a id="bcptTestFolders"></a>bcptTestFolders | bcptTestFolders should be an array of folders (relative to project root), which contains performance test apps for this project. Apps in these folders are sorted based on dependencies and built, published and bcpt tests are run in that order.<br />You can also use full paths if apps are available in a folder on the machine where the Azure DevOps agent is running. | [ ] |
| <a id="pageScriptingTests"></a>pageScriptingTests | pageScriptingTests should be an array of page scripting test file specifications, relative to the project root. Examples of file specifications: `recordings/my*.yml` (for all yaml files in the recordings subfolder matching my\*.yml), `recordings` (for all \*.yml files in the recordings subfolder) or `recordings/test.yml` (for a single yml file) | [ ] |
| <a id="doNotRunPageScriptingTests"></a>doNotRunPageScriptingTests | When true, this setting forces the pipeline to NOT run the page scripting tests specified in pageScriptingTests. Note this setting can be set in a [workflow specific settings file](#where-are-the-settings-located) to only apply to that workflow | false |
| <a id="restoreDatabases"></a>restoreDatabases | restoreDatabases should be an array of events, indicating when you want to start with clean databases in the container. Possible events are: `BeforeBcpTests`, `BeforePageScriptingTests`, `BeforeEachTestApp`, `BeforeEachBcptTestApp`, `BeforeEachPageScriptingTest` | [ ] |
| <a id="preprocessorSymbols"></a>preprocessorSymbols | List of preprocessor symbols to use when building the apps. | [ ] |
| <a id="ignoredPreprocessorSymbols"></a>ignoredPreprocessorSymbols | List of preprocessor symbols that should be ignored when building the apps. This setting affects symbols defined in `preprocessorSymbols` as well as symbols from app.json (when building with artifact ////appjson) | [ ] |
| <a id="writableFolderPath"></a>writableFolderPath | Specifies a folder used by pipelines to store/cache build configuration, nuget packages or to build local app file library. Accounts configured to run DevOps agents must have write permissions to this folder. | [ ] |
| <a id="artifactUrlCacheKeepHours"></a>artifactUrlCacheKeepHours | Specifies how long the artifact url cache is valid (in hours). If this value is different from 0, all requests for the same artifact (for example "**/Sandbox//au/latest**" (which is the same as "**////latest**" if you have country in settings set to AU)) will skip calling BcContainerHelper and will use the same artifactUrl. | 6 |
| <a id="nugetPackageCacheKeepDays"></a>nugetPackageCacheKeepDays | Specifies how long downloaded NuGet package content (dependency apps, symbols) is kept in the package cache under [writableFolderPath](#writableFolderPath) (in days, based on last usage). The version of each package to use is always resolved online, so a newer published version is always picked up - only the download of an already-known package version is skipped. Set to 0 to disable the package cache. The cache is not used when writableFolderPath is not set. | 14 |
| <a id="hybridDeploymentGitHubRepoSCId"></a>hybridDeploymentGitHubRepoSCId | Specifies the ID of the Service Connection that links the Azure DevOps with GitHub where the repository is located. This value is mandatory for hybrid deployments and ignored for standard, Azure DevOps only, deployments. |  |
| <a id="appDeliverToType"></a>appDeliverToType | Specifies the name of the delivery target for app files to package repository. | Apps |
| <a id="testDeliverToType"></a>testDeliverToType | Specifies the name of the delivery target for test files to package repository. | Tests |

## AppSource specific basic project settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="appSourceCopMandatoryAffixes"></a>appSourceCopMandatoryAffixes | This setting is only used if the type is AppSource App. The value is an array of affixes, which is used for running AppSource Cop. | [ ] |
| <a id="obsoleteTagMinAllowedMajorMinor"></a>obsoleteTagMinAllowedMajorMinor | This setting will enable AppSource cop rule AS0105, which causes objects that are pending obsoletion with an obsolete tag version lower than the minimum set in this property are not allowed. | |

## Basic Repository settings

| Name | Description |
| :-- | :-- |
| <a id="type"></a>type | Specifies the type of repository. Allowed values are **PTE** or **AppSource App**. |
| <a id="buildModes"></a>buildModes | A list of build modes to use when building the project. Every project will be built using each build mode. The following build modes have special meaning:<br /> **Default**: Apps are compiled as they are in the source code.<br />**Clean**: Should be used for Clean Mode. Use [Conditional Settings](#conditional-settings) with buildMode set the 'Clean' to specify preprocessorSymbols for clean mode.<br />**Translated**: `TranslationFile` compiler feature is enabled when compiling the apps.<br /><br />It is also possible to specify custom build modes by adding a build mode that is different than 'Default', 'Clean' or 'Translated' and use [conditional settings](#conditional-settings) to specify preprocessor symbols and other build settings for the build mode. |

## Advanced settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="artifact"></a>artifact | Determines the artifacts used for building and testing the app. The format and behavior depends on the **runWith** engine:<br /><br />**When runWith is BCContainerHelper:**<br />This setting can either be an absolute pointer to Business Central artifacts (https://... - rarely used) or it can be a search specification for artifacts (\<storageaccount>/\<type>/\<version>/\<country>/\<select>). All segments except version are optional — empty segments default to: storageAccount=*empty*, type=Sandbox, country=value from `country` setting, select=latest.<br />If not specified, the artifacts used will be the latest sandbox artifacts from the country specified in the country setting.<br />**Note:** if version is set to `*`, then the application dependency from the apps in your project will determine which artifacts to use. If select is *first*, then you will get the first artifacts matching your application dependency. If select is *latest* then you will get the latest artifacts with the same major.minor as your application dependency. If select is *appjson* then system will scan the app.json file and will request the latest artifact from the same minor version.<br /><br />**When runWith is NuGet:**<br />The artifact must be in the format `//version//` or `////keyword`. Only one of version or keyword should be populated. Valid keywords are: **latest** (current BC wave), **nextMinor** (next minor version of current wave), **nextMajor** (next major wave), **appjson** (version from app.json application property). Version should be in at least `X.Y` format. Examples: `////latest`, `//25.1//`, `////appjson`. | |
| <a id="updateDependencies"></a>updateDependencies | Setting updateDependencies to true causes to build your app against the first compatible Business Central build and set the dependency version numbers in the app.json accordingly during build. All version numbers in the built app will be set to the version number used during compilation. | false |
| <a id="generateDependencyArtifact"></a>generateDependencyArtifact | When this repository setting is true, CI/CD pipeline generates an artifact with the external dependencies used for building the apps in this repo. | false |
| <a id="companyName"></a>companyName | Company name selected in the database, used for running the CI/CD workflow. Default is to use the default company in the selected Business Central localization. | |
| <a id="versioningStrategy"></a>versioningStrategy | The versioning strategy determines how versioning is performed in this project. The version number of an app consists of 4 segments: **Major**.**Minor**.**Build**.**Revision**. **Major** and **Minor** are read from the app.json file for each app and **Build** and **Revision** are calculated (for most of the strategies). Currently 5 versioning strategies are supported:<br />**0** = **Build** is the **Azure DevOps [build_number](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml)** for the CI/CD workflow, increased by the **buildNumberOffset** setting value (if specified). **Revision** is the **Azure DevOps [jobattempt](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml)** subtracted 1.<br />**2** = **Build** is the current date as **yyyyMMdd**. **Revision** is the current time as **HHmmss** (24-hour format). Date and time are always **UTC** timezone to avoid problems during daylight savings time change (see **versioningTimeOffset** if you want to offset from UTC). Note that if two CI/CD workflows are started within the same second, this could yield identical version numbers from two different runs.<br />**3** = **Build** is taken from **app.json** (like Major and Minor) and **Revision** is the **Azure DevOps [build_number](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml)** for the CI/CD workflow, increased by the **buildNumberOffset** setting value (if specified).<br />**10** = the whole version **Major**.**Minor**.**Build**.**Revision** is taken from **app.json**. No version segments are calculated by the pipeline.<br />**+16** use **repoVersion** setting as **appVersion** (**Major**.**Minor**) for all apps. Can be combined with other strategies (e.g. 16 uses repoVersion with Build/Revision from strategy 0). | 0 |
| <a id="additionalCountries"></a>additionalCountries | This property can be set to an additional number of countries to compile, publish and test your app against during workflows. Note that this setting can be different in NextMajor and NextMinor workflows compared to the CI/CD workflow, by specifying a different value in a workflow settings file. | [ ] |
| <a id="appDependencies"></a>appDependencies | This property can be set to specify dependencies that should be installed together with the app. You do not need to specify dependencies included in the app.json file as they are included automatically. | [ ] |
| <a id="appDependenciesNuGet"></a>appDependenciesNuGet | This property can be set to specify dependencies that should be installed together with the app that are available in available NuGet feeds. You must specify NuGet Package name. You do not need to specify dependencies included in the app.json file as they are included automatically. | [ ] |
| <a id="testDependencies"></a>testDependencies | This property can be set to specify dependencies that should be installed together with the app. You do not need to specify dependencies included in the app.json file as they are included automatically. | [ ] |
| <a id="testDependenciesNuGet"></a>testDependenciesNuGet | This property can be set to specify dependencies that should be installed together with the app that are available in available NuGet feeds. You must specify NuGet Package name. You do not need to specify dependencies included in the app.json file as they are included automatically. | [ ] |
| <a id="installApps"></a>installApps | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting should be an array of either secure URLs or paths to folders or files relative to the project, where the CI/CD workflow can find and download the apps. The apps in installApps are downloaded and installed before compiling and installing the apps. | [ ] |
| <a id="installAppsNuGet"></a>installAppsNuGet | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting must be available in available NuGet feeds. You must specify NuGet Package name. The apps in installApps are downloaded and installed before compiling and installing the apps. | [ ] |
| <a id="installTestApps"></a>installTestApps | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting should be an array of either secure URLs or paths to folders or files relative to the project, where the CI/CD workflow can find and download the apps. The apps in installTestApps are downloaded and installed before compiling and installing the test apps. | [ ] |
| <a id="installTestAppsNuGet"></a>installTestAppsNuGet | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting must be available in available NuGet feeds. You must specify NuGet Package name. The apps in installTestAppsNuGet are downloaded and installed before compiling and installing the test apps. | [ ] |
| <a id="configPackages"></a>configPackages | An array of configuration packages to be applied to the build container before running tests. Configuration packages can be the relative path within the project or it can be STANDARD, EXTENDED or EVALUATION for the rapidstart packages, which comes with Business Central. | [ ] |
| <a id="configPackages.country"></a>configPackages.country | An array of configuration packages to be applied to the build container for country **country** before running tests. Configuration packages can be the relative path within the project or it can be STANDARD, EXTENDED or EVALUATION for the rapidstart packages, which comes with Business Central. | [ ] |
| <a id="installOnlyReferencedApps"></a>installOnlyReferencedApps | By default, only the apps referenced in the dependency chain of your apps will be installed when inspecting the settings: InstallApps, InstallAppsNuGet, InstallTestApps, InstallTestAppsNuGet and appDependencyProbingPath. If you change this setting to false, all apps found will be installed. | true |
| <a id="enableCodeCop"></a>enableCodeCop | If enableCodeCop is set to true, the workflow will enable the CodeCop analyzer when building. | false |
| <a id="enableUICop"></a>enableUICop | If enableUICop is set to true, the workflow will enable the UICop analyzer when building. | false |
| <a id="enableALCopsLinterCop"></a>enableALCopsLinterCop | If set to true, the workflow will enable the [ALCops LinterCop](https://alcops.dev/docs/analyzers/lintercop/) analyzer when building. Flags code quality issues, measures complexity, and promotes modern AL patterns. This is the successor to enableLinterCop. | false |
| <a id="enableALCopsApplicationCop"></a>enableALCopsApplicationCop | If set to true, the workflow will enable the [ALCops ApplicationCop](https://alcops.dev/docs/analyzers/applicationcop/) analyzer when building. Enforces Business Central application conventions for tables, pages, enums, labels, and permissions. | false |
| <a id="enableALCopsDocumentationCop"></a>enableALCopsDocumentationCop | If set to true, the workflow will enable the [ALCops DocumentationCop](https://alcops.dev/docs/analyzers/documentationcop/) analyzer when building. Validates that AL code is properly documented with comments and XML documentation. | false |
| <a id="enableALCopsFormattingCop"></a>enableALCopsFormattingCop | If set to true, the workflow will enable the [ALCops FormattingCop](https://alcops.dev/docs/analyzers/formattingcop/) analyzer when building. Enforces consistent code formatting and visual structure. | false |
| <a id="enableALCopsPlatformCop"></a>enableALCopsPlatformCop | If set to true, the workflow will enable the [ALCops PlatformCop](https://alcops.dev/docs/analyzers/platformcop/) analyzer when building. Detects code that is technically broken, dangerous, or silently ignored at the AL platform level. | false |
| <a id="enableALCopsTestAutomationCop"></a>enableALCopsTestAutomationCop | If set to true, the workflow will enable the [ALCops TestAutomationCop](https://alcops.dev/docs/analyzers/testautomationcop/) analyzer when building. Validates the structure and correctness of AL test code. | false |
| <a id="alcopsVersion"></a>alcopsVersion | Specifies the version of the ALCops.Analyzers NuGet package to use. Set to **latest** to automatically resolve the latest stable version. Set to **preview** to automatically resolve the latest prerelease version. Alternatively, specify an explicit version number (e.g. "1.0.0"). | latest |
| <a id="customCodeCops"></a>customCodeCops | CustomCodeCops is an array of paths or URLs to custom Code Cop DLLs you want to enable when building. Do not add LinterCop or ALCops as custom code cops, use the dedicated **enableLinterCop** or **enableALCops\*** settings instead. | [ ] |
| <a id="enableCodeAnalyzersOnTestApps"></a>enableCodeAnalyzersOnTestApps | If enableCodeAnalyzersOnTestApps is set to true, the code analyzers will be enabled when building test apps as well. | false |
| <a id="failOn"></a>failOn | Specifies what the pipeline will fail on. Allowed values are none, warning and error | error |
| <a id="rulesetFile"></a>rulesetFile | Filename of the custom ruleset file | |
| <a id="enableExternalRulesets"></a>enableExternalRulesets | If enableExternalRulesets is set to true, then you can have external rule references in the ruleset | false |
| <a id="vsixFile"></a>vsixFile | Determines which version of the AL Language Extension to use for building the apps. This can be:<br />**empty/not set** (default) to use the AL Language Extension which ships with the Business Central version you are building for<br />**latest** to always download the latest AL Language Extension from the marketplace<br />**preview** to always download the preview AL Language Extension from the marketplace.<br/>or a **direct download URL** pointing to the AL Language VSIX file to use for building the apps.<br />By default, BCDevOps Flows uses the AL Language extension, which is shipped with the artifacts used for the build. This setting only applies when **runWith** is BCContainerHelper. | |
| <a id="skipUpgrade"></a>skipUpgrade | This setting is used to signal to the pipeline to NOT run upgrade and ignore previous releases of the app. | false |
| <a id="cacheImageName"></a>cacheImageName | When using self-hosted runners, cacheImageName specifies the prefix for the docker image created for increased performance |  |
| <a id="cacheFolder"></a>cacheFolder | When using self-hosted runners, cacheFolder specifies where to store downloaded artifacts. Based on the cacheKeepDays the stored artifacts are reused by all pipelines that have the same artifact. | bcartifacts.cache |
| <a id="cacheFolderOld"></a>cacheFolderOld | When you change the cacheFolder to a new folder, you can use cacheFolderOld to cleanup the previous folder. When this value is populated, all artifacts in configured folder are automatically deleted during the next pipeline run that uses BCContainerHelper. This will cause all other running builds using the old folder to fail.  |  |
| <a id="cacheKeepDays"></a>cacheKeepDays | When using self-hosted runners, cacheKeepDays specifies the number of days docker image are cached before cleaned up when running the next pipeline.<br />Note that setting cacheKeepDays to 0 will flush the cache before every build and will cause all other running builds using agents on the same host to fail. | 3 |
| <a id="assignPremiumPlan"></a>assignPremiumPlan | Setting assignPremiumPlan to true in your project setting file, causes the build container to be created with the AssignPremiumPlan set. This causes the auto-created user to have Premium Plan enabled. This setting is needed if your tests require premium plan enabled. | false |
| <a id="enableTaskScheduler"></a>enableTaskScheduler | Setting enableTaskScheduler to true in your project setting file, causes the build container to be created with the Task Scheduler running. | false |
| <a id="removeInternalsVisibleTo"></a>removeInternalsVisibleTo | Setting removeInternalsVisibleTo to true will remove internalsVisibleTo property for app.json before building the app. | true for AppSource apps, false for PTE |
| <a id="overrideResourceExposurePolicy"></a>overrideResourceExposurePolicy | Setting overrideResourceExposurePolicy to true will override resource exposure policies with values from settings (allowDebugging, allowDownloadingSource, includeSourceInSymbolFile, applyToDevExtension). | false |
| <a id="allowDebugging"></a>allowDebugging | Specifies new value for allowDebugging resource exposure policy. If the setting is not configured, the existing value defined in the app.json is used. overrideResourceExposurePolicy must be enabled in order to use configured value. |  |
| <a id="allowDownloadingSource"></a>allowDownloadingSource | Specifies new value for allowDownloadingSource resource exposure policy. If the setting is not configured, the existing value defined in the app.json is used. overrideResourceExposurePolicy must be enabled in order to use configured value. |  |
| <a id="includeSourceInSymbolFile"></a>includeSourceInSymbolFile | Specifies new value for includeSourceInSymbolFile resource exposure policy. If the setting is not configured, the existing value defined in the app.json is used. overrideResourceExposurePolicy must be enabled in order to use configured value. |  |
| <a id="applyToDevExtension"></a>applyToDevExtension | Specifies new value for applyToDevExtension resource exposure policy. If the setting is not configured, the existing value defined in the app.json is used. overrideResourceExposurePolicy must be enabled in order to use configured value. |  |
| <a id="trustMicrosoftNuGetFeeds"></a>trustMicrosoftNuGetFeeds | Unless this setting is set to false, BC DevOps Flows will trust the NuGet feeds provided by Microsoft. The feeds provided by Microsoft contains all Microsoft apps, all Microsoft symbols and symbols for all AppSource apps. | true |
| <a id="generateCountryPreprocessorSymbols"></a>generateCountryPreprocessorSymbols | If enabled, BC DevOps Flows automatically generates preprocessor symbols in the format `COUNTRY_XX` for each country code from both the `country` and `additionalCountries` settings. Any existing `COUNTRY_XX` symbols from app.json are replaced with the generated ones. | false |
| <a id="versioningTimeOffset"></a>versioningTimeOffset | Offset in hours from UTC used for versioning strategy **2** (datetime-based). Use this if you want Build/Revision segments to be calculated in a timezone other than UTC. For example, use `12.0` for NZ timezone (UTC+12). Decimal values are supported. | 0.0 |
| <a id="doNotPublishApps"></a>doNotPublishApps | When true, this setting forces the pipeline to NOT publish the apps after building. | false |
| <a id="treatTestFailuresAsWarnings"></a>treatTestFailuresAsWarnings | When true, test failures are treated as warnings instead of errors, allowing the pipeline to complete successfully even if tests fail. | false |
| <a id="externalSettingsLink"></a>externalSettingsLink | Specifies link to a json file that contains settings that should be used for all projects and repositories. The link must use http or https. The external settings file is loaded as the first source in the settings merge order (see [Where are the settings located](#where-are-the-settings-located)). Note: if this setting is defined in a repository or pipeline settings file, the entire settings resolution is re-run with the external file included. |  |

## AppSource specific advanced settings

| Name | Description | Default value |
| :-- | :-- | :-- |

## Conditional Settings

In any of the settings files, you can add conditional settings by using the ConditionalSettings setting.

Example, adding this:

```json
    "ConditionalSettings": [
        {
            "branches": [
                "feature/*"
            ],
            "settings": {
                "doNotPublishApps": true,
                "doNotSignApps": true
            }
        }
    ]
```

to your [repository settings file](#where-are-the-settings-located) will ensure that all branches matching the patterns in branches will use doNotPublishApps=true and doNotSignApps=true during CI/CD. Conditions can be:

- **repositories** settings will be applied to repositories matching the patterns.
- **buildModes** settings will be applied when building with these buildModes.
- **branches** settings will be applied to branches matching the patterns. For pull request pipelines the target branch is used as the identifier.
- **workflows** settings will be applied to workflows matching the patterns.
- **users** settings will be applied for users matching the patterns.

You could imagine that you could have and organizational settings variable containing:

```json
    "ConditionalSettings": [
        {
            "repositories": [
                "bcsamples-*"
            ],
            "branches": [
                "features/*"
            ],
            "settings": {
                "doNotSignApps": true
            }
        }
    ]
```

Which will ensure that for all repositories named `bcsamples-*` in this organization, the branches matching `features/*` will not sign apps.

> [!NOTE]
> You can have conditional settings on any level and all conditional settings which has all conditions met will be applied in the order of settings file + appearance.

## Expert settings (rarely used)

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="repoName"></a>repoName | the name of the repository | name of Azure DevOps repository |
| <a id="buildNumberOffset"></a>buildNumberOffset | when using **VersioningStrategy** 0 or 3, the CI/CD workflow uses the Azure DevOps BUILD_NUMBER as part of the version number as described under VersioningStrategy. The BUILD_NUMBER is ever increasing and if you want to reset it, when increasing the Major or Minor parts of the version number, you can specify a negative number as buildNumberOffset. You can also provide a positive number to get a starting offset. Read about BUILD_NUMBER [here](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml) | 0 |
| <a id="applicationDependency"></a>applicationDependency | Application dependency defines the lowest Business Central version supported by your app (Build will fail early if artifacts used are lower than this). The value is calculated by reading app.json for all apps, but cannot be lower than the applicationDependency setting which has a default value of 25.0.0.0 | 25.0.0.0 |
| <a id="installTestRunner"></a>installTestRunner | Determines whether the test runner will be installed in the pipeline. If there are testFolders in the project, this setting will be true. | calculated |
| <a id="installTestFramework"></a>installTestFramework | Determines whether the test framework apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the test framework apps, this setting will be true | calculated |
| <a id="installTestLibraries"></a>installTestLibraries | Determines whether the test libraries apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the test library apps, this setting will be true | calculated |
| <a id="installPerformanceToolkit"></a>installPerformanceToolkit | Determines whether the performance test toolkit apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the performance test toolkit apps, this setting will be true | calculated |
| <a id="enableAppSourceCop"></a>enableAppSourceCop | Determines whether the AppSourceCop will be enabled in the pipeline. If the project type is AppSource App, then the AppSourceCop will be enabled by default. You can set this value to false to force the AppSourceCop to be disabled. | true for AppSource apps |
| <a id="enablePerTenantExtensionCop"></a>enablePerTenantExtensionCop | Determines whether the PerTenantExtensionCop will be enabled in the pipeline. If the project type is PTE, then the PerTenantExtensionCop will be enabled by default. You can set this value to false to force the PerTenantExtensionCop to be disabled. | true for PTE apps |
| <a id="updateAppSourceCop"></a>updateAppSourceCop | Specifies whether the Pipeline should update/create an AppSourceCop file in the repository. This setting is respected only when the pipeline is configured to Increment Version. Use this option in pipelines when you increase the version and you want users to validate breaking changes against the new version. | false |
| <a id="doNotBuildTests"></a>doNotBuildTests | This setting forces the pipeline to NOT build and run the tests and performance tests in testFolders and bcptTestFolders | false |
| <a id="doNotRunTests"></a>doNotRunTests | This setting forces the pipeline to NOT run the tests in testFolders. Tests are still being built and published. Note this setting can be set in a [workflow specific settings file](#where-are-the-settings-located) to only apply to that workflow | false |
| <a id="doNotRunBcptTests"></a>doNotRunBcptTests | This setting forces the pipeline to NOT run the performance tests in bcptTestFolders. Performance tests are still being built and published. Note this setting can be set in a [workflow specific settings file](#where-are-the-settings-located) to only apply to that workflow | false |
| <a id="memoryLimit"></a>memoryLimit | Specifies the memory limit for the build container. By default, this is left to BcContainerHelper to handle and will currently be set to 8G | 8G |
| <a id="BcContainerHelperVersion"></a>BcContainerHelperVersion | This setting can be set to a specific version (ex. 3.0.8) of BcContainerHelper to force BCDevOps Flows to use this version. **latest** means that BCDevOps Flows will use the latest released version. **preview** means that BCDevOps Flows will use the latest preview version. **none** means that BCDevOps Flows will use the BcContainerHelper module already installed on the build agent. Using a specific version is not recommended and will show a warning. This setting applies only when **runWith** is BCContainerHelper. | preview |
| <a id="failPublishTestsOnFailureToPublishResults"></a>failPublishTestsOnFailureToPublishResults | By default, all projects with enabled tests expect test results. If there are no test results available, the **Publish Test Results** step fails. If you set this setting to false, missing or corrupted tests are considered as successful. | true |
| <a id="skipAppSourceCopMandatoryAffixesEnforcement"></a>skipAppSourceCopMandatoryAffixesEnforcement | Use this option to skip mandatory enforcement of the Affixes. For example, if you have one PTE project without affixes, you can use this option in combination with custom rule set to suppress enforcement and validation. | false |
| <a id="recreatePipelineInSetupPipeline"></a>recreatePipelineInSetupPipeline | When set to true, the SetupPipelines step will delete and recreate existing pipelines in Azure DevOps. Without this, existing pipelines are skipped. You must enable this property when you change the workflowSchedule (cron), workflowTrigger, workflowPRTrigger, or any other pipeline YAML-level setting for a pipeline that already exists in Azure DevOps. | false |

______________________________________________________________________

[back](../README.md)