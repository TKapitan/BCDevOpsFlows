# Configure Azure DevOps Variables

Azure DevOps variables allows to change behaviour of pipelines (including BCDevOps Flows) without changing files.

## Create Variable Group

Variable group is an entity that groups variables. To access the variable from a pipeline, pipeline must have permission to access the variable group assigned to the variable.

1. Navigate to your Azure DevOps project.
2. Click on "Pipelines" -> "Library" -> "+ Variable Group"
3. Set the name to "BCDevOpsFlows" (you can use different name, but you will need to update all yaml files).

## Supported Variables

### AL_ENVIRONMENTS (mandatory for DeployToCloud step)

JSON structured list of environments available for deployment. **The variable must be compressed JSON!** The example below is structured json only for better readability.

```json
{
    "Specifies name of the environment for deployement. Must match the environment name.": {
        "environmentName": "Specifies name of the environment for deployement. Must match the environment name.",
        "buildMode": "Only 'Default' is currently supported.",
        "dependencyInstallMode": "Allowed values: ignore, install, upgrade or forceUpgrade",
        "authContextVariableName": "Name of the secret variable (NAME OF THE VARIABLE, NOT THE AUTHCONTEXT!!!) that contains authContext"
    },
    "---Environment2Name---": {
        "environmentName": "---Environment2Name---",
        "buildMode": "'default'",
        "dependencyInstallMode": "ignore",
        "authContextVariableName": "---authContext_YYY---"
    }
}
```

### AL_AUTHCONTEXTS (mandatory for DeployToCloud step, must be marked as secret)

JSON structured list of available authentication contexts for deployment. **The variable must be compressed JSON!** The example below is structured json only for better readability. The variable must be set as secret and must be explicitly specified for every step that should have the variable available (if you use recommended names, standard pipelines are preconfigured).

The variable name in the library should match the value of `BCDevOpsFlowsAuthContextVarName` setting (default: `AL_AUTHCONTEXT`). In pipeline YAML files, the secret variable is mapped to `AL_AUTHCONTEXTS_INTERNAL` (secret variables must be explicitly passed in YAML).

```json
{
    "Specifies name of the authContext variable. This must match the value of authContextVariableName parameter in AL_ENVIRONMENTS environment variable": {
        "tenantID": "Specifies the tenant ID of the environment you want to deploy the app to.",
        "clientID": "Specifies the client ID of the app allowed to connect to the environment.",
        "clientSecret": "Specifies the client secret of the app allowed to connect to the environment."
    },
    "---authContext_YYY---": {
        "tenantID": "---TenantId---",
        "clientID": "---clientID---",
        "clientSecret": "---clientSecret---"
    }
}
```

### AL_TRUSTEDNUGETFEEDS (mandatory for NuGet dependency resolution, must be marked as secret)

JSON structured list of trusted NuGet feeds used to retrieve dependency packages. **The variable must be compressed JSON!** You do not need to include Microsoft NuGet feeds as they are included automatically.

The variable name in the library should match the value of `BCDevOpsFlowsTrustedNuGetFeedVarName` setting (default: `AL_TRUSTEDNUGETFEEDS`). In pipeline YAML files, the secret variable is mapped to `AL_TRUSTEDNUGETFEEDS_INTERNAL` (secret variables must be explicitly passed in YAML).

```json
[
    {
        "Name": "---Feed 1 Name---",
        "Url": "---Feed 1 Url---",
        "Token": "---Feed 1 Token (with Read permission)---"
    },
    {
        "Name": "---Feed 2 Name---",
        "Url": "---Feed 2 Url---",
        "Token": "---Feed 2 Token (with Read permission)---"
    }
]
```

### AL_DELIVERTO (mandatory for DeliverAppFile step, must be marked as secret)

JSON configuration specifying where app and test app files should be delivered. **The variable must be compressed JSON!** The `NugetFeedName` must match the `Name` of one of feeds defined in AL_TRUSTEDNUGETFEEDS.

```json
{
    "Apps": {
        "type": "AzureDevOps",
        "NugetFeedName": "---Feed Name for app delivery---"
    },
    "Tests": {
        "type": "NuGet",
        "NugetFeedName": "---Feed Name for test app delivery---"
    }
}
```

### AL_CICD_ENVIRONMENTNAMEFILTERS (mandatory for CI/CD deployment)

Specifies environment name or names that should be used by the CI/CD pipeline. This can be an exact environment name or a RegExp based on environment names from AL_ENVIRONMENTS. Note: CI/CD pipeline automatically ignores production environments even if they match the filter. If only production environments match, the deployment step will fail.

### AL_PROD_ENVIRONMENTNAMESFILTER (mandatory for Publish to Production deployment)

Specifies environment name or names that should be used by the Publish to Production pipeline. This can be an exact environment name or a RegExp based on environment names from AL_ENVIRONMENTS. This step supports both production and sandbox environments.

### AL_PROJECTSETTINGS (optional)

You can use the variable to specify/override default settings. The variable must be compressed json. For more details see [Settings Overview](../SettingsOverview.md).

### AL_DEBUG (optional)

If set to 'true', the output log contains additional details. If you are submitting an issue with BCDevOps Flows, you must run the pipeline with this variable enabled and provide the log generated with this variable enabled.
