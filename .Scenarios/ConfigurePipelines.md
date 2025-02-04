# Configure Pipelines in your repository

_Prerequisities: Existing BCDevOps Flows project (see [Create New project](./CreateNewProject.md) or [Add BCDevOps Flows to Existing Project](./AddBCDevOpsFlowsToExistingProject.md))_

Now, when you have BC DevOps Flows project you are ready to configure pipelines.

## Update BC DevOps Files

Before you create Azure DevOps pipelines, you must update BCDevOps flows template.

1. Open your local BCDevOps Flows repository you want to configure.
1. Update default .yaml files
    - Replace `# Specify the link to your BCDevOpsFlows fork (format YourGitHubUsername/ForkName)` with name of your repository that hosts the fork/clone of BCDevOpsFlows scripts (usually `GitHubUserName/GitHubRepositoryName`)
    - Replace `# Specify the name of the service connection with access to your fork` with the name of your service connection (see [Connect Azure DevOps with GitHub](./HowToStart/ConnectAzureDevOpsWithGitHub.md))
    - Replace `# Specify the name of the pool of your self-hosted agents` with the name of your agent pool that hosts your self-hosted agents (see [Configure Agent Pool](./HowToStart/ConfigureAgentPool.md))
1. Update default .yaml files (mandatory for Deploy to Cloud only)
    - Replace `# Specify the name of the environment to deploy to` with a name of environment you want the pipeline to deploy the apps. The value must match values specified in **AL_ENVIRONMENTS** environment variable (see [Configure Azure DevOps Variables](./HowToStart/ConfigAzureDevOpsVariables.md))
1. You can create your own yaml files by combining supported steps. See the documentation in BCDevOpsFlows for every step to understand mandatory and optional variables.

## Configure Azure DevOps pipelines

1. Push your changes to Azure DevOps.
1. Navigate to the Azure Devops project.
1. Select **Pipelines** -> **New Pipeline**
1. Select **Azure Repos Git** -> Select your repository -> **Existing Azure Pipelines YAML file**
1. Select the branch where your files are located and the file -> **Continue**.
1. Click on the arrow next to **Run** and select **Save**.
1. **Run Pipeline**
1. (optional) based on your setup, you may need to grant access to the variable group and runner group. Open the pipeline once you clicked **Run Pipeline** and grant access to everything needed.
