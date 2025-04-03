Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCDevOpsFlows.Setup.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

if (!$ENV:AL_SETTINGS) {
    Write-Error "ENV:AL_SETTINGS not found. The Read-Settings step must be run before this step."
}
$settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable

if ([string]::IsNullOrEmpty($settings.pipelineBranch)) {
    Write-Error "settings.pipelineBranch is required but was not provided."
}

$pipelineFolderPath = switch ($settings.pipelineFolderStructure) {
    'Repository' { $ENV:BUILD_REPOSITORY_NAME }
    'Pipeline' { $ENV:BUILD_DEFINITIONNAME }
    'Path' { $settings.pipelineFolderPath }
    '' { '' }
    default { Write-Error "Invalid settings.pipelineFolderStructure: $($settings.pipelineFolderStructure)";  }
}
if ($pipelineFolderPath -eq '') {
    $pipelineFolderPath = '\'
}
OutputDebug "Using pipeline folder path: $pipelineFolderPath"

OutputDebug "Adding Azure DevOps extension to Azure CLI"
az extension add -n azure-devops

$yamlFolder = "$ENV:BUILD_REPOSITORY_LOCALPATH\$scriptsFolderName"
$yamlFiles = Get-ChildItem -Path $yamlFolder -Filter *.yml -File
if ($null -eq $yamlFiles -or $yamlFiles.Count -eq 0) {
    Write-Error "No YAML files found in $yamlFolder"
}
OutputDebug "Preparing pipelines for project '$ENV:SYSTEM_TEAMPROJECT' in organization '$ENV:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI'"
foreach ($pipelineYamlFilePath in $yamlFiles) {
    $pipelineName = $pipelineYamlFilePath.BaseName
    $pipelineYamlFileRelativePath = "$scriptsFolderName\$($pipelineYamlFilePath.BaseName).yml"
    
    OutputDebug "Creating pipeline '$pipelineName' with YAML file '$pipelineYamlFileRelativePath' in folder '$pipelineFolderPath'"

    az pipelines create `
        --name "$pipelineName" `
        --folder-path "$pipelineFolderPath" `
        --organization "$ENV:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI" `
        --project "$ENV:SYSTEM_TEAMPROJECT" `
        --description "Pipeline $pipelineName created by SetupPipelines." `
        --repository "$ENV:BUILD_REPOSITORY_NAME" `
        --branch $settings.pipelineBranch `
        --yml-path "$pipelineYamlFileRelativePath" `
        --repository-type "tfsgit" `
        --skip-first-run $settings.pipelineSkipFirstRun
}
