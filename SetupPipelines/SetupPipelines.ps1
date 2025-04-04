Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "SetupPipelines.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCDevOpsFlows.Setup.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\YamlClass.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\GitHelper.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

if (!$ENV:AL_SETTINGS) {
    Write-Error "ENV:AL_SETTINGS not found. The Read-Settings step must be run before this step."
}
$settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable

if ([string]::IsNullOrEmpty($settings.pipelineBranch)) {
    Write-Error "settings.pipelineBranch is required but was not provided."
}

Install-AzureCLIDevOpsExtension

$yamlPipelineFolder = "$ENV:BUILD_REPOSITORY_LOCALPATH\$scriptsFolderName"
$yamlPipelineTemplateFolder = "$yamlPipelineFolder\Templates"
if ($null -eq $yamlPipelineTemplateFolder -or $yamlPipelineTemplateFolder.Count -eq 0) {
    Write-Error "No YAML files found in template folder $yamlPipelineTemplateFolder"
}
Copy-PipelineTemplateFilesToPipelineFolder -templateFolderPath $yamlPipelineTemplateFolder -targetPipelineFolderPath $yamlPipelineFolder
Invoke-GitAddCommit -appFolderPath$yamlPipelineFolder -commitMessage "Restore BCDevOpsFlows from template"
Invoke-GitPush "HEAD:$($settings.pipelineBranch)"

$pipelineDevOpsFolderPath = Get-PipelineDevOpsFolderPath -settings $settings
$yamlFiles = Get-ChildItem -Path $yamlPipelineFolder -Filter *.yml -File
OutputDebug "Preparing pipelines for project '$ENV:SYSTEM_TEAMPROJECT' in organization '$ENV:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI'"
foreach ($pipelineYamlFilePath in $yamlFiles) {
    $pipelineName = $pipelineYamlFilePath.BaseName
    $pipelineYamlFileRelativePath = "$scriptsFolderName\$($pipelineYamlFilePath.BaseName).yml"
    
    Add-AzureDevOpsPipelineFromYaml `
        -pipelineName $pipelineName `
        -pipelineFolder $pipelineDevOpsFolderPath `
        -pipelineBranch $settings.pipelineBranch `
        -pipelineYamlFileRelativePath $pipelineYamlFileRelativePath `
        -skipPipelineFirstRun $settings.pipelineSkipFirstRun
}
