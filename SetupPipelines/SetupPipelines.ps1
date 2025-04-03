Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

az extension add -n azure-devops
az devops configure --defaults organization="$ENV:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI" project="$ENV:SYSTEM_TEAMPROJECT" --use-git-aliases true

$yamlFolder = "$ENV:BUILD_REPOSITORY_LOCALPATH\.azure-pipelines\Templates"
$yamlFiles = Get-ChildItem -Path $yamlFolder -Filter *.yml -File
foreach ($pipelineYamlFilePath in $yamlFiles) {
    $pipelineName = $pipelineYamlFilePath.BaseName
    $pipelineYamlFileRelativePath = ".azure-pipelines\Templates\$($pipelineYamlFilePath.BaseName).yml"
    
    OutputDebug "az pipelines create --name $pipelineName --description 'Test' --repository $ENV:BUILD_REPOSITORY_NAME --branch test --yml-path $pipelineName"
    az pipelines create --name "$pipelineName-2" --folder-path "Test" --description "Test" --repository "$ENV:BUILD_REPOSITORY_NAME" --branch "test" --yml-path "$pipelineYamlFileRelativePath" --repository-type "tfsgit"
}
