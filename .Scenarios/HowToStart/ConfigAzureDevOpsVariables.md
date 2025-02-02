# Configure Azure DevOps Variables

Azure DevOps variables allows to change behaviour of pipelines (including BCDevOps Flows) without changing files.

## Create Variable Group

Variable group is an entity that groups variables. To access the variable from a pipeline, pipeline must have permission to access the variable group assigned to the variable.

1. Navigate to your Azure DevOps project.
2. Click on "Pipelines" -> "Library" -> "+ Variable Group"
3. Set the name to "BCDevOpsFlows" (you can use different name, but you will need to update all yaml files).

## Supported Variables

### AL_BCDEVOPSFLOWS (mandatory)

Specifies the repository with your version of BCDevOps Flows. Must have format (GitHubOwner/RepositoryName).

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

### AL_AUTHCONTEXT (mandatory for DeployToCloud step, must be marked as secret)

JSON structured list of available authentication contexts for deployment. **The variable must be compressed JSON!** The example below is structured json only for better readability. The variable must be set as secret and must be explicitly specified for every step that should have the variable available (if you use recommended names, standard pipelines are preconfigured).

```json
{
    "Specifies name of the authContext variable. This must match the value of authContextVariableName parameter in AL_ENVIRONMENTS environment variable": {
        "tenantID": "Specifies the tenant ID of the environment you want to deploy the app to.",
        "clientID": "Specifies the client ID of the app allowed to connect to the environment.",
        "clientSecret": "Specifies the client secret of the app allowed to connect to the environment."
    },
    "---authContext_YYY---": {
        "tenantID": "---TenantId---",
        "clientID": "'---clientID---'",
        "clientSecret": "---clientSecret---"
    }
}
```

### AL_PROJECTSETTINGS (optional)

You can use the variable to specify/override default settings. The variable must be compressed json. For more details see [Settings Overview](../SettingsOverview.md).

### AL_DEBUG (optional)

If set to 'true', the output log contains additional details. If you are submitting issue with the BCDevOps Flows, you must run the pipeline with this variable enable and provide log generated with this variable enabled.
