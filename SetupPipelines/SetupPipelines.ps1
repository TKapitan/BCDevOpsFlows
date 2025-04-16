Param()
$PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::PlainText;

. (Join-Path -Path $PSScriptRoot -ChildPath "SetupPipelines.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\ReadSettings\ReadSettings.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\BCDevOpsFlows.Setup.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\GitHelper.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Common\Import-Common.ps1" -Resolve)

$settings = ReadSettings -pipelineName '' -setupPipelineName "$ENV:AL_PIPELINENAME" -userName '' -branchName '' | ConvertTo-HashTable -recurse
if ([string]::IsNullOrEmpty($settings.pipelineBranch)) {
    Write-Error "settings.pipelineBranch is required but was not provided."
}

Install-AzureCLIDevOpsExtension

$yamlPipelineFolder = "$ENV:BUILD_REPOSITORY_LOCALPATH\$scriptsFolderName"
$yamlPipelineTemplateFolder = "$yamlPipelineFolder\Templates"
if ($null -eq $yamlPipelineTemplateFolder -or $yamlPipelineTemplateFolder.Count -eq 0) {
    Write-Error "No YAML files found in template folder $yamlPipelineTemplateFolder"
}

try {
    Set-Location $ENV:BUILD_REPOSITORY_LOCALPATH
    Set-GitUser
    Invoke-RestoreUnstagedChanges -appFolderPath $yamlPipelineFolder
    Copy-PipelineTemplateFilesToPipelineFolder -templateFolderPath $yamlPipelineTemplateFolder -targetPipelineFolderPath $yamlPipelineFolder
    Invoke-GitAddCommit -appFolderPath $yamlPipelineFolder -commitMessage "Restore BCDevOpsFlows from template"
    Update-PipelineYMLFiles -templateFolderPath $yamlPipelineTemplateFolder -pipelineFolderPath $yamlPipelineFolder
    Invoke-GitAddCommit -appFolderPath $yamlPipelineFolder -commitMessage "Update BCDevOpsFlows from setup"
}
catch {
    Write-Host $_.Exception -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host $_.PSMessageDetails

    Write-Error "Error when updating pipelines. See previous lines for details."
}
finally {
    Set-GitUser
    Pop-Location
}
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
