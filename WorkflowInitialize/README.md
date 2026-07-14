# Initialize Workflow

This workflow is used to initialize the environment for the other workflows. It can be used to set up any necessary resources, such as databases, storage accounts, or other services that are required for the other workflows to run.

As part of initialization, it cleans up leftover build folders before the build, in case a previous run left non-expected files behind. The following folders under `$ENV:PIPELINE_WORKSPACE\App` are removed if they exist:

- `.buildpackages`
- `.buildartifacts\Dependencies`
- `.buildartifacts\TestApps`
- `.buildartifacts\Apps`
- `.output`

When the `pipelineSelfHealing` setting is enabled, initialization also checks whether the pipeline YAML files in the repository still match the current settings. If they drifted, the corrected files are committed and pushed back to the pipeline branch with `[skip azurepipelines]`, so settings changes apply on the next run without re-running SetupPipelines. Pipeline templates stay pristine: they only ever receive the central `CustomLogic/PipelineYamlPatches.json` changes, never settings-derived values or variable name replacements. Self-healing is skipped for pull request builds, for runs on branches other than `pipelineBranch`, and for the SetupPipelines workflow itself; failures only log a warning and never fail the build.

## INPUT Parameters

No parameters.

## ENV INPUT variables

| Name                  | Description |
| :--                   | :-- |
| AL_PIPELINENAME       | Specifies the name of the pipeline. Used by self-healing to determine the pipeline-specific settings and to skip critical workflows. If not set, self-healing does not run. |

## ENV OUTPUT variables

No environment output parameters.
