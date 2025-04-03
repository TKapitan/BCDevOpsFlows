Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

az extension add -n azure-devops
az devops configure --defaults organization="$ENV:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI" project="$ENV:SYSTEM_TEAMPROJECT" --use-git-aliases true

$yamlFolder = "$ENV:BUILD_REPOSITORY_LOCALPATH\.azure-pipelines\Templates"
$yamlFiles = Get-ChildItem -Path $yamlFolder -Filter *.yml -File
foreach ($pipelineYamlFilePath in $yamlFiles) {
    $pipelineName = $pipelineYamlFilePath.BaseName
    $pipelineYamlFileRelativePath = ".azure-pipelines\Templates\$($pipelineYamlFilePath.BaseName).yml"
    
    OutputDebug "Creating pipeline '$pipelineName' with YAML file '$pipelineYamlFileRelativePath'"
    az pipelines create --name "$pipelineName" --folder-path "Test" --description "Test" --repository "$ENV:BUILD_REPOSITORY_NAME" --branch "TKA-dev" --yml-path "$pipelineYamlFileRelativePath" --repository-type "tfsgit"
}
