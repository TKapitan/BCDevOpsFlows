# Initialize Workflow

Initialize the workflow and create a telemetry scope for tracking pipeline execution time. This step should be run as the first step in any pipeline.

## INPUT Parameters

No parameters.

## ENV INPUT variables

| Name | Description |
| :-- | :-- |
| AL_DEBUG | If set to 'true', pipelines generate additional logs that provide better details. If requesting support, you must provide a log generated when this variable is enabled. |

## ENV OUTPUT variables

| Name | Description |
| :-- | :-- |
| AL_TELEMETRYSCOPE | A telemetry scope JSON object that contains the workflow start time, used for tracking pipeline execution duration. |
