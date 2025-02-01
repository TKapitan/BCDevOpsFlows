# Read settings

Allows to store the generated app file in local (or shared) folder for usage in other pipelines as dependencies or as steps of other pipelines.

## INPUT Parameters

| Name                  | Required  | Description                                                               | Default value |
| :--                   | :-:       | :--                                                                       | :--           |
| buildMode             | No        | Specifies BuildMode. It's used for conditional settings.                  |               |
| get                   | No        | Specifies which properties to get from the settings file, default is all. |               |

## ENV INPUT variables

| Name                  | Description                                                       |
| :--                   | :--                                                               |
| AL_PROJECTSETTINGS    | Compressed json file with settings to be used for this project.   |

## ENV OUTPUT variables

| Name              | Description                                           |
| :--               | :--                                                   |
| AL_SETTINGS       | Compressed json file with BCDevOpsFlows settings.     |