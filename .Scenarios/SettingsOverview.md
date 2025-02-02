# BCDevOps Flows Settings Overview

This page explains the configuration parameters supported by BCDevOps Flows.

## Different Settings Levels

BCDevOps Flows offers 4 different levels of configuration. These levels are evaluated in sequence with the first level having the lowest priority (if the same property is specified in two different levels, the lower level is used).

1. Azure DevOps project setting (environment variable AL_PROJECTSETTINGS)
1. Repository settings (.azure-pipelines/BCDevOpsFlows-Settings.json)
1. Pipeline settings (.azure-pipelines/\<pipelineName\>.settings.json)  
    - \<pipelineName\> is specified in AL_PIPELINENAME environment variable
    - If this environment variable is not found, the predefined Azure DevOps variable (Build.DefinitionName) is used instead.
1. User settings (.azure-pipelines/\<userReqForEmail\>.settings.json)
    - Example: Tom@bccaptain.com.au.Settings.json

## Settings Overview

TODO create table of supported configuration
