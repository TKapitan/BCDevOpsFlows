# Verify Authentication Context

Verify configuration of auth context and deploy to cloud settings

## INPUT Parameters

| Name                  | Required  | Description                                                                                       | Default value         |
| :--                   | :-:       | :--                                                                                               | :--                   |
| environmentName       | Yes       | Name of environment to deploy to                                                                  |                       |

## ENV INPUT variables

| Name                  | Description |
| :--                   | :-- |
| AL_ENVIRONMENTS       | Specifies details about all available environments. It must contain details about the environment used as $(environmentName) INPUT parameter. See chapter below for details about the content. |
| AL_AUTHCONTEXTS_INTERNAL        | Specifies authentication context of the Entra app allowed to connect to Business Central. See chapter below for details about the content. In default setup, configure AL_AUTHCONTEXTS variable in your library and pass it to AL_AUTHCONTEXTS_INTERNAL variable in yaml file (secret variables must be explicitly configured in yaml files). |
| AL_DEBUG | If set to 'true', pipelines generate additional logs that provides better details. If requesting support, you must provide log generated when this variable is enabled. |

## ENV OUTPUT variables

No environment output parameters.
