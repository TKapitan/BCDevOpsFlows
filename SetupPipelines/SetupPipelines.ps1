Param()

# Install Azure DevOps extension
az extension add -n azure-devops

# Show Azure CLI version
az --version

# Set the default Azure DevOps organization and project
az devops configure --defaults organization=$ENV:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI project= $ENV:SYSTEM_TEAMPROJECT --use-git-aliases true

# Show build list and PRs
az pipelines build list
git pr list
