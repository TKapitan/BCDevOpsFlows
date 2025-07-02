# Configure Pipelines for Hybrid Deployment

_Prerequisities: Existing BCDevOps Flows project (see [Create New project](./CreateNewProject.md) or [Add BCDevOps Flows to Existing Project](./AddBCDevOpsFlowsToExistingProject.md)) created as Hybrid Deployment. GitHub and Azure DevOps configured for Hybrid Deployment (see [Setup GitHub](../HybridDeployment/SetupGitHub.md) and [Setup Azure DevOps](../HybridDeployment/SetupAzureDevOps.md))_

**This document describes Hybrid Deployment with Repository in GitHub, everything else in Azure DevOps. For standard deployment (everything in Azure DevOps), see [Configure Pipelines](../ConfigurePipelines.md)**

Now, when you have BC DevOps Flows project configured for Hybrid Deployment and both GitHub and Azure DevOps configured you are ready to configure pipelines.

## Update Pipeline Settings

Configure BCDevOps Flows json setting files
1. Open your local repository that contains BCDevOpsFlows yaml files.
1. Navigate to **".azure-pipelines"** folder where you can update the generic settings file **"BCDevOpsFlows.settings.json"** that should contain settings applicable to all pipelines.
1. Navigate to **".azure-pipelines"** folder where you can update the generic settings file **"SetupPipelines.settings.json"** that should contain settings applicable to pipeline setup.
1. Navigate to **".azure-pipelines/Templates"** folder where you can update pipeline-specific settings. !!!IMPORTANT!!! once you run **SetupPipelines** pipeline (see below) the settings files are copied to **".azure-pipelines"** folder and files in the template folder are ignored. To change setup once the pipelines are configure, use files in **".azure-pipelines"** folder.

## Update BC DevOps Files

Before you create Azure DevOps pipelines, you must update BCDevOps flows template.
1. Create Azure DevOps Service Connection, see [Connect Azure DevOps with GitHub](./HowToStart/ConnectAzureDevOpsWithGitHub.md) for more details.
1. Create a pool of self-hosted agents, see [Configure Agent Pool](./HowToStart/ConfigureAgentPool.md) for more details.
1. Open your local repository that contains BCDevOpsFlows yaml files.
1. Navigate to **".azure-pipelines"** folder and open **"SetupPipelines.yml"**
1. Replace 
    - **name: ------ REPLACE -------** with name of your GitHub repository that contains your copy of BCDevOpsFlows (format **"UserName/RepositoryName"**)
    - **endpoint: ------ REPLACE -------** with name of your Azure DevOps Service Connection configured to access your BCDevOpsFlows GitHub repository
    - **ref: ------ REPLACE -------** name of the branch from your BCDevOpsFlows repository you want to use

## Configure Azure DevOps pipelines

1. Push your changes to GitHub.
1. Navigate to the Azure Devops project.
1. Select **Pipelines** -> **New Pipeline**
1. Select **GitHub** (GitHub Enterprise Server is not supported) -> Authorize the access -> Select your repository -> Review the selected repository and click on **Approve & Install** -> **Existing Azure Pipelines YAML file**
1. Select the branch where your files are located and the file **".azure-pipelines/SetupPipelines.yml"** -> **Continue**.
1. Click on the arrow next to **Run** and select **Save**.
1. **Run Pipeline**
1. Once the pipeline is completed, you will see all pipelines in Azure DevOps and configured based on provided setup.
