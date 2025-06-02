# Read settings

Allows to store the generated app file in local (or shared) folder for usage in other pipelines as dependencies or as steps of other pipelines.

## INPUT Parameters

| Name                  | Required  | Description                                                               | Default value |
| :--                   | :-:       | :--                                                                       | :--           |
| buildMode             | No        | Specifies BuildMode. It's used for conditional settings.                  |               |
| get                   | No        | Specifies which properties to get from the settings file as global variables (in format 'AL_XX' where XX is the property name. Name is always converted to upper case), default is blank/none (except the variables required by BCDevOpsFlows, see **ENV OUTPUT variables**). |               |

## ENV INPUT variables

| Name                  | Description                                                       |
| :--                   | :--                                                               |
| AL_PROJECTSETTINGS    | Compressed json file with settings to be used for this project.   |
| AL_PIPELINENAME       | Specifies the name of the pipeline. This value is used to determine setting file for the pipeline-specific configuration. If this value is blank, the predefined Build.DefinitionName environment variable (pipeline name as configured in devops) is used.  |
| AL_DEBUG | If set to 'true', pipelines generate additional logs that provides better details. If requesting support, you must provide log generated when this variable is enabled. |

## ENV OUTPUT variables

| Name              | Description                                           |
| :--               | :--                                                   |
| AL_SETTINGS       | Compressed json file with BCDevOpsFlows settings.     |
| AL_FAILPUBLISHTESTSONFAILURETOPUBLISHRESULTS | Specifies if the run should fail when Test app is configured and no test results are generated. This may indicate issue in the pipeline or that the configured Test app does not have any tests implemented.     |
| AL_RUNWITH           | Specifies whether to use NuGet or BCContainerHelper to build the app. |
| AL_ALLOWPRERELEASE   | If set to true, pipeline will use public releases as well as preview/prerelease builds. |
