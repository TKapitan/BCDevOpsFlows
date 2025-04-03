Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "WriteOutput.Helper.ps1" -Resolve)

az extension add -n azure-devops
az devops configure --defaults organization="$ENV:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI" project="$ENV:SYSTEM_TEAMPROJECT" --use-git-aliases true

$yamlFolder = "$ENV:BUILD_REPOSITORY_LOCALPATH\.azure-pipelines\Templates"
$yamlFiles = Get-ChildItem -Path $yamlFolder -Filter *.yml -File
foreach ($pipelineYamlFile in $yamlFiles) {
    $pipelineName = $pipelineYamlFile.BaseName
    
    OutputDebug "az pipelines create --name $pipelineName --description 'Test' --repository $ENV:BUILD_REPOSITORY_NAME --branch test --yml-path $pipelineName"
    az pipelines create --name $pipelineName --description 'Test' --repository $ENV:BUILD_REPOSITORY_NAME --branch test --yml-path $pipelineName
}
