. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

function Get-PipelineDevOpsFolderPath {
    Param(
        [Parameter(Mandatory = $true)]
        $settings
    )

    switch ($settings.pipelineFolderStructure) {
        'Repository' {
            $pipelineFolderPath = $ENV:BUILD_REPOSITORY_NAME
        }
        'Pipeline' {
            $pipelineFolderPath = $ENV:BUILD_DEFINITIONNAME
        }
        'Path' {
            $pipelineFolderPath = $settings.pipelineFolderPath
        }
        '' { 
            $pipelineFolderPath = ''
        }
        default { 
            Write-Error "Invalid settings.pipelineFolderStructure: $($settings.pipelineFolderStructure)"
        }
    }
    if ($pipelineFolderPath -eq '') {
        $pipelineFolderPath = '\'
    }
    OutputDebug "Using pipeline folder path: $pipelineFolderPath for $($settings.pipelineFolderStructure)"
    return $pipelineFolderPath
}

function Install-AzureCLIDevOpsExtension {
    Param()

    OutputDebug "Adding Azure DevOps extension to Azure CLI"
    az extension add -n azure-devops
}

function Add-AzureDevOpsPipelineFromYaml {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $pipelineName,
        [Parameter(Mandatory = $true)]
        [string] $pipelineFolder,
        [Parameter(Mandatory = $true)]
        [string] $pipelineBranch,
        [Parameter(Mandatory = $true)]
        [string] $pipelineYamlFileRelativePath,
        [Parameter(Mandatory = $false)]
        [bool] $skipPipelineFirstRun = $false
    )

    OutputDebug "Creating pipeline '$pipelineName' for branch '$pipelineBranch' with YAML file '$pipelineYamlFileRelativePath' in folder '$pipelineFolder'"
    if($skipPipelineFirstRun) {
        OutputDebug "Skipping first run of pipeline '$pipelineName'"
    }

    # az pipelines create `
    #     --name "$pipelineName" `
    #     --folder-path "$pipelineFolder" `
    #     --organization "$ENV:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI" `
    #     --project "$ENV:SYSTEM_TEAMPROJECT" `
    #     --description "Pipeline $pipelineName created by SetupPipelines." `
    #     --repository "$ENV:BUILD_REPOSITORY_NAME" `
    #     --branch $pipelineBranch `
    #     --yml-path "$pipelineYamlFileRelativePath" `
    #     --repository-type "tfsgit" `
    #     --skip-first-run $skipPipelineFirstRun
}

function Copy-PipelineTemplateFilesToPipelineFolder {
    param (
        [Parameter(Mandatory = $true)]
        [string]$templateFolderPath,
        [Parameter(Mandatory = $true)]
        [string]$targetPipelineFolderPath
    )

    if (-not (Test-Path -Path $templateFolderPath -PathType Container)) {
        Write-Error "Pipeline Template folder does not exist: $templateFolderPath"
    }
    if (-not (Test-Path -Path $targetPipelineFolderPath -PathType Container)) {
        Write-Error "Target Pipeline folder does not exist: $targetPipelineFolderPath"
    }

    OutputDebug "Copying files from template folder '$templateFolderPath' to '$targetPipelineFolderPath'"
    Get-ChildItem -Path $templateFolderPath -File -Recurse | ForEach-Object {
        if (Test-Path -Path (Join-Path -Path $targetPipelineFolderPath -ChildPath $_.Name)) {
            OutputDebug "Restoring pipeline from template: $($_.Name)"
        } else {
            OutputDebug "Creating new pipeline from template: $($_.Name)"
        }
        $targetFile = Join-Path -Path $targetPipelineFolderPath -ChildPath $_.Name
        Copy-Item -Path $_.FullName -Destination $targetFile -Force
    }
}