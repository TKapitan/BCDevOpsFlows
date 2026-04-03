# Add BCDevOps Flows to Existing Project

You are ready to add BCDevOps Flows to your existing project!

1. Clone the template repository located here https://github.com/TKapitan/BCDevOpsFlowsTemplate
1. Clone your own repository.
1. Move all your AL app files in your repository to an **App** folder (and optionally **Test** folder for your test app). Each folder should contain one AL project.
1. If you do not have a test app in your repository, copy the **Test** folder from the BCDevOpsFlows template repository.
1. Copy the **.azure-pipelines** folder from the template repository to your repository.
1. Copy the .gitignore file from the template repository. You may need to merge it with your own .gitignore file if you have additional files excluded/included.
1. Push all changes to your Azure DevOps*

NEXT STEP: [Configure Pipelines](./ConfigurePipelines.md)

*) or GitHub for Hybrid Deployment, see [Setup GitHub for Hybrid Deployment](./HybridDeployment/SetupGitHub.md) and [Setup Azure DevOps for Hybrid Deployment](./HybridDeployment/SetupAzureDevOps.md)
