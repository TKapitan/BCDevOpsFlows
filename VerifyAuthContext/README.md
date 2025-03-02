# Verify Authentication Context

Verify configuration of auth context and deploy to cloud settings

## INPUT Parameters

| Name                  | Required  | Description                                                                                       | Default value         |
| :--                   | :-:       | :--                                                                                               | :--                   |
| environmentsNameFilter       | Yes       | Name of environment where to verify authcontext. You can also use RegEx to specify filter for environment names where to verify authcontext    |                       |

## ENV INPUT variables

| Name                  | Description |
| :--                   | :-- |
| AL_ENVIRONMENTS       | Specifies details about all available environments. It must contain details about the environment used as $(environmentName) INPUT parameter. See chapter below for details about the content. |
| AL_CICD_ENVIRONMENTNAMEFILTERS | Specifies environment or environments that should be used by the CI/CD pipeline. This can be exact environment name or RegExp based on environment names. Note: CI/CD pipeline automatically ignores production environments even if they are specified in the parameters. If only production environment is specified, the step will fail. |
| AL_PROD_ENVIRONMENTNAMESFILTER | Specifies environment or environments that should be used by the publish to production pipeline. This can be exact environment name or RegExp based on environment names. Note: This step supports both production and sandbox environments. |
| AL_AUTHCONTEXTS_INTERNAL        | Specifies authentication context of the Entra app allowed to connect to Business Central. See chapter below for details about the content. In default setup, configure AL_AUTHCONTEXTS variable in your library and pass it to AL_AUTHCONTEXTS_INTERNAL variable in yaml file (secret variables must be explicitly configured in yaml files). |
| AL_DEBUG | If set to 'true', pipelines generate additional logs that provides better details. If requesting support, you must provide log generated when this variable is enabled. |

## ENV OUTPUT variables

No environment output parameters.
