# Set up Azure DevOps for Hybrid Deployment

## First connect and link Azure DevOps Boards with GitHub

1. Open Azure DevOps project
1. Navigate to "**Project Settings**"
1. "**Boards**" -> "**GitHub Connections**"
1. Choose "**Connect your GitHub account**" to use your GitHub account credentials.
1. Click "**Authorize AzureBoards**"
1. Select the repository you want the project connect to, confirm, review and continue using "**Approve, Install, & Authorize**"
1. "**Pipelines**" -> "**Service Connections**"
1. Open the service connection created for the GitHub Connection (usually named using the GitHub organization name)
1. Click on three dots in right top corner -> "**Security**"
1. Add access to all pipelines (or enable unrestricted access)
1. Click "**Add**" in the "**User permissions**" section, find the build service from the current project (always called "**Project Name Build Service (DevOps Organization Name)**" and set the role to "**User**")
