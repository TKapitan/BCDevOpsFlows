Param()

# Install Azure DevOps extension
az extension add -n azure-devops

# Set the default Azure DevOps organization and project
az devops configure --defaults organization="$ENV:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI" project="$ENV:SYSTEM_TEAMPROJECT" --use-git-aliases true

# Show build list and PRs
az pipelines build list
git pr list

$yamlFolder = "$ENV:BUILD_REPOSITORY_LOCALPATH\.azure-pipelines\Templates"
$yamlFiles = Get-ChildItem -Path $yamlFolder -Filter *.yml -File
foreach ($pipelineYamlFile in $yamlFiles) {
    $pipelineName = $pipelineYamlFile.BaseName
    az pipelines create --name $pipelineName --description 'Test' --branch test --yml-path $pipelineName
}
