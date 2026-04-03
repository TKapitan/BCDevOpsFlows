# Pipeline Cleanup

Clean up the pipeline after completion or in case of unexpected failure. Removes Docker containers (if BCContainerHelper was used), NuGet build package caches, and runs any configured custom cleanup logic.

## INPUT Parameters

No input parameters.

## ENV INPUT variables

| Name                  | Description |
| :--                   | :-- |
| AL_CONTAINERNAME | If specified, system will try to remove the container and clean up any remaining container files or running processes. This may happen if the build step fails. |
| AL_NUGETINITIALIZED   | If set to true, system cleans NuGet-specific build package caches. |
| AL_BCCONTAINERHELPERPATH | If specified and valid, system will not download and import a new BCContainerHelper. This is usually configured in the background to prevent downloading/importing BCContainerHelper in every step. |
| AL_DEBUG | If set to 'true', pipelines generate additional logs that provides better details. If requesting support, you must provide log generated when this variable is enabled. |

## ENV OUTPUT variables

| Name                      | Description                               |
| :--                       | :--                                       |
| AL_BCCONTAINERHELPERPATH  | Path to the BC Container Helper module. Set when container cleanup is performed (i.e., when AL_CONTAINERNAME is specified). |