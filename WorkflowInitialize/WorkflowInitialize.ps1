Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Common\Import-Common.ps1" -Resolve)

try {
    # Clean up leftover build folders before the build in case a previous run left non-expected files behind
    $baseRepoFolder = "$ENV:PIPELINE_WORKSPACE\App"
    $cleanUpPaths = @(
        "$baseRepoFolder\.buildpackages"
        "$baseRepoFolder\.buildartifacts\Dependencies"
        "$baseRepoFolder\.buildartifacts\TestApps"
        "$baseRepoFolder\.buildartifacts\Apps"
        "$baseRepoFolder\.output"
    )
    foreach ($cleanUpPath in $cleanUpPaths) {
        if (Test-Path $cleanUpPath) {
            Write-Host "Removing leftover files from $cleanUpPath"
            Remove-Item $cleanUpPath -Recurse -Force
        }
    }

    # Best effort: reclaim containers a previous canceled run may have left behind. Canceled runs
    # skip later steps unless the pipeline marks them with condition: always(), so the cleanup step
    # never ran for them. Only runs on Azure DevOps agents inside a BCDevOpsFlows workflow.
    if ($ENV:TF_BUILD -eq 'True' -and $ENV:AL_PIPELINENAME -and (Get-Command docker -ErrorAction SilentlyContinue)) {
        try {
            . (Join-Path -Path $PSScriptRoot -ChildPath "..\CustomLogic\RunCustomCleanup.ps1" -Resolve)
            Write-Host "Cleaning up containers left behind by previous runs"
            RunCustomCleanup
        }
        catch {
            Write-Host "::Warning::Could not clean up leftover containers: $($_.Exception.Message)"
        }
    }

    # Best effort: self-heal pipeline YAML drift against settings (opt-in via pipelineSelfHealing)
    # so setting changes roll out on the next run without re-running SetupPipelines. Only runs on
    # Azure DevOps agents inside a BCDevOpsFlows workflow and must never fail the build.
    if ($ENV:TF_BUILD -eq 'True' -and $ENV:AL_PIPELINENAME -and $ENV:BUILD_REPOSITORY_LOCALPATH) {
        try {
            . (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\PipelineYaml.Helper.ps1" -Resolve)
            Invoke-PipelineYamlSelfHeal
        }
        catch {
            Write-Host "::Warning::Could not self-heal pipeline YAML files: $($_.Exception.Message)"
        }
    }
}
catch {
    Write-Host "##vso[task.logissue type=error]$($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($_.PSMessageDetails) {
        Write-Host $_.PSMessageDetails
    }
    Write-Host "##vso[task.complete result=Failed]"
    exit 0
}
