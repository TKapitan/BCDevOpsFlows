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

### **IMPORTANT - run SetupPipelines pipeline to apply this settings** 
This setup is not applied until you run the **SetupPipelines** pipeline. **SetupPipelines** pipeline must be created manually and must be run whenever any of the following settings is changed.

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="pipelineBranch"></a>pipelineBranch | Specify what branch should be used in Azure DevOps to run pipelines from. | main |
| <a id="pipelineFolderStructure"></a>pipelineFolderStructure | Specifies the parent folder for pipelines in Azure DevOps. This settings is not a folder in repository, but folder in Azure DevOps Pipelines (Project -> Pipelines -> All -> folders). Allowed values: "Repository" - repository name is used as folder, "Pipeline" - pipeline name is used as folder, "Path" - manually specified path in "pipelineFolderPath" property (see below) | Repository |
| <a id="pipelineFolderPath"></a>pipelineFolderPath | Specifies the folder path in Azure DevOps pipelines. Only applicable when pipelineFolderStructure is set to Path. Leave blank and set pipelineFolderStructure to Path if you do not want to use folders. |  |
| <a id="pipelineSkipFirstRun"></a>pipelineSkipFirstRun | When a new pipeline is created in Azure DevOps, it's automatically run to test the setup and permissions. We recommend to always run the pipeline after it is created to verify setup and permissions. | $false |
| <a id="BCDevOpsFlowsPoolName"></a>BCDevOpsFlowsPoolName | Name of the Azure DevOps Pool that hosts your self-hosted agents. The project must have access to the pool. Once pipelines are created for the first time, you must allow access to the Pool in Azure DevOps. | SelfHostedWindows |
| <a id="BCDevOpsFlowsPoolNameCICD"></a>BCDevOpsFlowsPoolNameCICD | Name of the Azure DevOps Pool that hosts your self-hosted agents. This agent pool is used for CICD pipeline. If blank/not specified, the value from **BCDevOpsFlowsPoolName** is used instead. You can use different Agent Pool to have different pool approvals and check (e.g. business hours). See Microsoft Learn for more details https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals?view=azure-devops&tabs=check-pass |  |
| <a id="BCDevOpsFlowsPoolNamePublishToProd"></a>BCDevOpsFlowsPoolNamePublishToProd | Name of the Azure DevOps Pool that hosts your self-hosted agents. This agent pool is used for PublishToProduction pipeline. If blank/not specified, the value from **BCDevOpsFlowsPoolName** is used instead. You can use different Agent Pool to have different pool approvals and check (e.g. business hours). See Microsoft Learn for more details https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals?view=azure-devops&tabs=check-pass |  |
| <a id="BCDevOpsFlowsResourceRepositoryName"></a>BCDevOpsFlowsResourceRepositoryName | Specifies name of the GitHub repository where you host your version of BCDevOpsFlows (format "owner/repositoryname") |  |
| <a id="BCDevOpsFlowsResourceRepositoryBranch"></a>BCDevOpsFlowsResourceRepositoryBranch | Specifies what branch from your GitHub BCDevOpsFlows repository you want to use. | main |
| <a id="BCDevOpsFlowsServiceConnectionName"></a>BCDevOpsFlowsServiceConnectionName | Specifies name of Azure DevOps Service Connection that is configured and allowed to access your GitHub with BCDevOpsFlows scripts. |  |
| <a id="BCDevOpsFlowsVariableGroup"></a>BCDevOpsFlowsVariableGroup | Specifies name of the variable group in your Azure DevOps pipeline that hosts environment variables. Once pipelines are created for the first time, you must allow access to the Pool in Azure DevOps. |  |
| <a id="workflowTrigger"></a>workflowTrigger | Specifies pipeline triggers. See documentation at Microsoft Learn to learn more about structure https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/azure-repos-git?view=azure-devops&tabs=yaml#ci-triggers. This settings is available for all pipelines except "PullRequest". | Set for CICD and PublishToProduction pipelines |
| <a id="workflowSchedule"></a>workflowSchedule | Specifies schedule when the pipeline should be automatically run. See documentation at Microsoft Learn to learn more about structure https://learn.microsoft.com/en-us/azure/devops/pipelines/process/scheduled-triggers. This settings is available for all pipelines except "PullRequest". | Set for TestCurrent, TestNextMinor and TestNextMajor |
| <a id="updateVersionNumber"></a>updateVersionNumber | Specifies the version (relative or absolute) to what the app version should be updated to. This setting is applied only to CICD and PublishToProduction pipelines. You can use both relative (+1, +0.1, ...) or absolute (1, 23.5, ...) notations. You must use only values allowed by the versionStrategy. If the version strategy calculates automatically last two digits, you cannot specify version that includes the third digit etc. |  |
| <a id="externalSettingsLink"></a>externalSettingsLink | Specifies link to json file that contains settings that should be used for all projects and repositories. This path could be http or https. While technically changing this value does not require running the **SetupPipelines** pipeline, it is highly recommended to do so, as the file can contain any of the options above. |  |
| <a id="runWith"></a>runWith | Specifies the engine that is used for Build tasks in pipelines. By default, the BCContainerHelper is used for all builds except CICD and PublishToProduction pipelines. | BcContainerHelper/NuGet |
| <a id="allowPrerelease"></a>allowPrerelease | Specifies whether the prerelease (preview) packages should be used as AL dependencies. | No |

#### Differences in runWith - BCContainerHelper vs. NuGet

Table below shows what functionality is currently supported in BCDevOps Flows by the engine.

|                                     | BCContainerHelper | NuGet     |
| :--                                 | :--               | :--       |
| Build an app file                   | Supported         | Supported |
| Fail the build on error             | Supported         | Supported |
| Fail the build on warning           | Supported         | -         |
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
| <a id="country"></a>country | Specifies which country this app is built against. | us |
| <a id="repoVersion"></a>repoVersion | RepoVersion is the project version number. The Repo Version number consists of \<major>.\<minor> only and is used for naming build artifacts in the CI/CD workflow. Build artifacts are named **\<project>-Apps-\<repoVersion>.\<build>.\<revision>** and can contain multiple apps. The Repo Version number is used as major.minor for individual apps if versioningStrategy is +16. | 1.0 |
| <a id="appFolders"></a>appFolders | appFolders should be an array of folders (relative to project root), which contains apps for this project. Apps in these folders are sorted based on dependencies and built and published in that order.<br />You can also use full paths if apps are available in a folder on the machine where the Azure DevOps agent is running. | [ ] |
| <a id="testFolders"></a>testFolders | testFolders should be an array of folders (relative to project root), which contains test apps for this project. Apps in these folders are sorted based on dependencies and built, published and tests are run in that order.<br />You can also use full paths if apps are available in a folder on the machine where the Azure DevOps agent is running. | [ ] |
| <a id="bcptTestFolders"></a>bcptTestFolders | bcptTestFolders should be an array of folders (relative to project root), which contains performance test apps for this project. Apps in these folders are sorted based on dependencies and built, published and bcpt tests are run in that order.<br />You can also use full paths if apps are available in a folder on the machine where the Azure DevOps agent is running. | [ ] |
| <a id="pageScriptingTests"></a>pageScriptingTests | pageScriptingTests should be an array of page scripting test file specifications, relative to the project root. Examples of file specifications: `recordings/my*.yml` (for all yaml files in the recordings subfolder matching my\*.yml), `recordings` (for all \*.yml files in the recordings subfolder) or `recordings/test.yml` (for a single yml file) | [ ] |
| <a id="doNotRunpageScriptingTests"></a>doNotRunpageScriptingTests | When true, this setting forces the pipeline to NOT run the page scripting tests specified in pageScriptingTests. Note this setting can be set in a [workflow specific settings file](#where-are-the-settings-located) to only apply to that workflow | false |
| <a id="restoreDatabases"></a>restoreDatabases | restoreDatabases should be an array of events, indicating when you want to start with clean databases in the container. Possible events are: `BeforeBcpTests`, `BeforePageScriptingTests`, `BeforeEachTestApp`, `BeforeEachBcptTestApp`, `BeforeEachPageScriptingTest` | [ ] |
| <a id="preprocessorSymbols"></a>preprocessorSymbols | List of preprocessor symbols to use when building the apps. | [ ] |
| <a id="ignoredPreprocessorSymbols"></a>ignoredPreprocessorSymbols | List of preprocessor symbols that should be ignored when building the apps. This setting affects symbols defined in `preprocessorSymbols` as well as symbols from app.json (when building with artifact ////appjson) | [ ] |
| <a id="writableFolderPath"></a>writableFolderPath | Specifies a folder used by pipelines to store/cache build configuration, nuget packages or to build local app file library. Accounts configured to run DevOps agents must have write permissions to this folder. | [ ] |
| <a id="artifactUrlCacheKeepHours"></a>artifactUrlCacheKeepHours | Specifies how long the artifact url cache is valid (in hours). If this value is different from 0, all requests for the same artifact (for example "**/Sandbox//au/latest**" (which is the same as "**////latest**" if you have country in settings set to AU)) will skip calling BcContainerHelper and will use the same artifactUrl. | 6 |

## AppSource specific basic project settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="appSourceCopMandatoryAffixes"></a>appSourceCopMandatoryAffixes | This setting is only used if the type is AppSource App. The value is an array of affixes, which is used for running AppSource Cop. | [ ] |
| <a id="obsoleteTagMinAllowedMajorMinor"></a>obsoleteTagMinAllowedMajorMinor | This setting will enable AppSource cop rule AS0105, which causes objects that are pending obsoletion with an obsolete tag version lower than the minimum set in this property are not allowed. | |

## Basic Repository settings

| Name | Description |
| :-- | :-- |
| <a id="type"></a>type | Specifies the type of repository. Allowed values are **PTE** or **AppSource App**. |
| <a id="buildModes"></a>buildModes | A list of build modes to use when building the project. Every project will be built using each build mode. The following build modes have special meaning:<br /> **Default**: Apps are compiled as they are in the source code.<br />**Clean**: Should be used for Clean Mode. Use [Conditional Settings](https://aka.ms/algosettings#conditional-settings) with buildMode set the 'Clean' to specify preprocessorSymbols for clean mode.<br />**Translated**: `TranslationFile` compiler feature is enabled when compiling the apps.<br /><br />It is also possible to specify custom build modes by adding a build mode that is different than 'Default', 'Clean' or 'Translated' and use [conditional settings](https://aka.ms/algosettings#conditional-settings) to specify preprocessor symbols and other build settings for the build mode. |

## Advanced settings

| Name | Description | Default value |
| :-- | :-- | :-- |
| <a id="artifact"></a>artifact | Determines the artifacts used for building and testing the app.<br />This setting can either be an absolute pointer to Business Central artifacts (https://... - rarely used) or it can be a search specification for artifacts (\<storageaccount>/\<type>/\<version>/\<country>/\<select>).<br />If not specified, the artifacts used will be the latest sandbox artifacts from the country specified in the country setting.<br />**Note:** if version is set to `*`, then the application dependency from the apps in your project will determine which artifacts to use. If select is *first*, then you will get the first artifacts matching your application dependency. If select is *latest* then you will get the latest artifacts with the same major.minor as your application dependency. If select is *appjson* then sestem will scan the app.json file and wil request the latest artifact from the same minor version. | |
| <a id="updateDependencies"></a>updateDependencies | Setting updateDependencies to true causes to build your app against the first compatible Business Central build and set the dependency version numbers in the app.json accordingly during build. All version numbers in the built app will be set to the version number used during compilation. | false |
| <a id="generateDependencyArtifact"></a>generateDependencyArtifact | When this repository setting is true, CI/CD pipeline generates an artifact with the external dependencies used for building the apps in this repo. | false |
| <a id="companyName"></a>companyName | Company name selected in the database, used for running the CI/CD workflow. Default is to use the default company in the selected Business Central localization. | |
| <a id="versioningStrategy"></a>versioningStrategy | The versioning strategy determines how versioning is performed in this project. The version number of an app consists of 4 segments: **Major**.**Minor**.**Build**.**Revision**. **Major** and **Minor** are read from the app.json file for each app and **Build** and **Revision** are calculated (for most of the strategies). Currently 4 versioning strategies are supported:<br />**0** = **Build** is the **Azure DevOps [build_number](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml)** for the CI/CD workflow, increased by the **buildNumberOffset** setting value (if specified). **Revision** is the **Azure DevOps [jobattempt](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml)** subtracted 1.<br />**2** = **Build** is the current date as **yyyyMMdd**. **Revision** is the current time as **hhmmss**. Date and time are always **UTC** timezone to avoid problems during daylight savings time change (see **versioningTimeOffset** if you want to use different timezone). Note that if two CI/CD workflows are started within the same second, this could yield to identical version numbers from two different runs.<br />**3** = **Build** is taken from **app.json** (like Major and Minor) and **Revision** is the **Azure DevOps [build_number](https://go.microsoft.com/fwlink/?linkid=2217416&clcid=0x409)** for the CI/CD workflow<br />**10** = the whole version **Major**.**Minor**.**Build**.**Revision**. **Major** is taken from **app.json**<br />**+16** use **repoVersion** setting as **appVersion** for all apps | 0 |
| <a id="additionalCountries"></a>additionalCountries | This property can be set to an additional number of countries to compile, publish and test your app against during workflows. Note that this setting can be different in NextMajor and NextMinor workflows compared to the CI/CD workflow, by specifying a different value in a workflow settings file. | [ ] |
| <a id="appDependencies"></a>appDependencies | This property can be set to specify dependencies that should be installed together with the app. You do not need to specify dependencies included in the app.json file as they are included automatically. | [ ] |
| <a id="appDependenciesNuGet"></a>appDependenciesNuGet | This property can be set to specify dependencies that should be installed together with the app that are available in available NuGet feeds. You must specify NuGet Package name. You do not need to specify dependencies included in the app.json file as they are included automatically. | [ ] |
| <a id="testDependencies"></a>testDependencies | This property can be set to specify dependencies that should be installed together with the app. You do not need to specify dependencies included in the app.json file as they are included automatically. | [ ] |
| <a id="testDependenciesNuGet"></a>testDependenciesNuGet | This property can be set to specify dependencies that should be installed together with the app that are available in available NuGet feeds. You must specify NuGet Package name. You do not need to specify dependencies included in the app.json file as they are included automatically. | [ ] |
| <a id="installApps"></a>installApps | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting should be an array of either secure URLs or paths to folders or files relative to the project, where the CI/CD workflow can find and download the apps. The apps in installApps are downloaded and installed before compiling and installing the apps. | [ ] |
| <a id="installTestApps"></a>installTestApps | An array of 3rd party dependency apps, which you do not have access to through the appDependencyProbingPaths. The setting should be an array of either secure URLs or paths to folders or files relative to the project, where the CI/CD workflow can find and download the apps. The apps in installTestApps are downloaded and installed before compiling and installing the test apps. Adding a parantheses around the setting indicates that the test in this app will NOT be run, only installed. | [ ] |
| <a id="configPackages"></a>configPackages | An array of configuration packages to be applied to the build container before running tests. Configuration packages can be the relative path within the project or it can be STANDARD, EXTENDED or EVALUATION for the rapidstart packages, which comes with Business Central. | [ ] |
| <a id="configPackages.country"></a>configPackages.country | An array of configuration packages to be applied to the build container for country **country** before running tests. Configuration packages can be the relative path within the project or it can be STANDARD, EXTENDED or EVALUATION for the rapidstart packages, which comes with Business Central. | [ ] |
| <a id="installOnlyReferencedApps"></a>installOnlyReferencedApps | By default, only the apps referenced in the dependency chain of your apps will be installed when inspecting the settings: InstallApps, InstallTestApps and appDependencyProbingPath. If you change this setting to false, all apps found will be installed. | true |
| <a id="enableCodeCop"></a>enableCodeCop | If enableCodeCop is set to true, the CI/CD workflow will enable the CodeCop analyzer when building. | false |
| <a id="enableUICop"></a>enableUICop | If enableUICop is set to true, the CI/CD workflow will enable the UICop analyzer when building. | false |
| <a id="customCodeCops"></a>customCodeCops | CustomCodeCops is an array of paths or URLs to custom Code Cop DLLs you want to enable when building. | [ ] |
| <a id="enableCodeAnalyzersOnTestApps"></a>enableCodeAnalyzersOnTestApps | If enableCodeAnalyzersOnTestApps is set to true, the code analyzers will be enabled when building test apps as well. | false |
| <a id="failOn"></a>failOn | Specifies what the pipeline will fail on. Allowed values are none, warning and error | error |
| <a id="rulesetFile"></a>rulesetFile | Filename of the custom ruleset file | |
| <a id="enableExternalRulesets"></a>enableExternalRulesets | If enableExternalRulesets is set to true, then you can have external rule references in the ruleset | false |
| <a id="vsixFile"></a>vsixFile | Determines which version of the AL Language Extension to use for building the apps. This can be:<br />**default** to use the AL Language Extension which ships with the Business Central version you are building for<br />**latest** to always download the latest AL Language Extension from the marketplace<br />**preview** to always download the preview AL Language Extension from the marketplace.<br/>or a **direct download URL** pointing to the AL Language VSIX file to use for building the apps.<br />By default, BCDevOps Flows uses the AL Language extension, which is shipped with the artifacts used for the build. | default |
| <a id="skipUpgrade"></a>skipUpgrade | This setting is used to signal to the pipeline to NOT run upgrade and ignore previous releases of the app. | false |
| <a id="cacheImageName"></a>cacheImageName | When using self-hosted runners, cacheImageName specifies the prefix for the docker image created for increased performance |  |
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

- **repositories** settings will be applied to repositories matching the patterns
- **buildModes** settings will be applied when building with these buildModes
- **branches** settings will be applied to branches matching the patterns
- **workflows** settings will be applied to workflows matching the patterns
- **users** settings will be applied for users matching the patterns

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
| <a id="buildNumberOffset"></a>buildNumberOffset | when using **VersioningStrategy** 0, the CI/CD workflow uses the Azure DevOps BUILD_NUMBER as the build part of the version number as described under VersioningStrategy. The BUILD_NUMBER is ever increasing and if you want to reset it, when increasing the Major or Minor parts of the version number, you can specify a negative number as buildNumberOffset. You can also provide a positive number to get a starting offset. Read about BUILD_NUMBER [here](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml) | 0 |
| <a id="applicationDependency"></a>applicationDependency | Application dependency defines the lowest Business Central version supported by your app (Build will fail early if artifacts used are lower than this). The value is calculated by reading app.json for all apps, but cannot be lower than the applicationDependency setting which has a default value of 18.0.0.0 | 18.0.0.0 |
| <a id="installTestRunner"></a>installTestRunner | Determines whether the test runner will be installed in the pipeline. If there are testFolders in the project, this setting will be true. | calculated |
| <a id="installTestFramework"></a>installTestFramework | Determines whether the test framework apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the test framework apps, this setting will be true | calculated |
| <a id="installTestLibraries"></a>installTestLibraries | Determines whether the test libraries apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the test library apps, this setting will be true | calculated |
| <a id="installPerformanceToolkit"></a>installPerformanceToolkit | Determines whether the performance test toolkit apps will be installed in the pipeline. If the test apps in the testFolders have dependencies on the performance test toolkit apps, this setting will be true | calculated |
| <a id="enableAppSourceCop"></a>enableAppSourceCop | Determines whether the AppSourceCop will be enabled in the pipeline. If the project type is AppSource App, then the AppSourceCop will be enabled by default. You can set this value to false to force the AppSourceCop to be disabled. | true for AppSource apps |
| <a id="enablePerTenantExtensionCop"></a>enablePerTenantExtensionCop | Determines whether the PerTenantExtensionCop will be enabled in the pipeline. If the project type is PTE, then the PerTenantExtensionCop will be enabled by default. You can set this value to false to force the PerTenantExtensionCop to be disabled. | true for PTE apps |
| <a id="doNotBuildTests"></a>doNotBuildTests | This setting forces the pipeline to NOT build and run the tests and performance tests in testFolders and bcptTestFolders | false |
| <a id="doNotRunTests"></a>doNotRunTests | This setting forces the pipeline to NOT run the tests in testFolders. Tests are still being built and published. Note this setting can be set in a [workflow specific settings file](#where-are-the-settings-located) to only apply to that workflow | false |
| <a id="doNotRunBcptTests"></a>doNotRunBcptTests | This setting forces the pipeline to NOT run the performance tests in testFolders. Performance tests are still being built and published. Note this setting can be set in a [workflow specific settings file](#where-are-the-settings-located) to only apply to that workflow | false |
| <a id="memoryLimit"></a>memoryLimit | Specifies the memory limit for the build container. By default, this is left to BcContainerHelper to handle and will currently be set to 8G | 8G |
| <a id="BcContainerHelperVersion"></a>BcContainerHelperVersion | This setting can be set to a specific version (ex. 3.0.8) of BcContainerHelper to force BCDevOps Flows to use this version. **latest** means that BCDevOps Flows will use the latest released version. **preview** means that BCDevOps Flows will use the latest preview version. **dev** means that BCDevOps Flows will use the dev branch of containerhelper. | latest |
| <a id="failPublishTestsOnFailureToPublishResults"></a>failPublishTestsOnFailureToPublishResults | By default, all projects with enabled tests expect test results. If there are no test results available, the **Publish Test Results** step fails. If you set this setting to false, missing or corrupted tests are considered as successful. | true |
| <a id="skipAppSourceCopMandatoryAffixesEnforcement"></a>skipAppSourceCopMandatoryAffixesEnforcement | Use this option to skip mandatory enforcement of the Affixes. For example, if you have one PTE project without affixes, you can use this option in combination with custom rule set to suppress enforcement and validation. | false |
| <a id="recreatePipelineInSetupPipeline"></a>recreatePipelineInSetupPipeline | You must enable this property when you change the workflowSchedule (cron) for a pipeline that already exists in AzureDevOps. | false |

______________________________________________________________________

[back](../README.md)
