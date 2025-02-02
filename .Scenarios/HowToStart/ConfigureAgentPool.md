# Configure Azure DevOps Agent Pool

BCDevOps Flows currently support only self-hosted agents (Azure DevOps agents hosted on your server/VM).

To configure Agent Pool
1. Go to "Project Settings" in your Azure DevOps project.
1. Click on "Agent pools" and "Add pool".
1. Select "Self-hosted" and set a name for the pool. You need to specify this name in all yaml files.

To add an Agent to existing Agent Pool
1. Open an "Agent Pool".
1. Click on "New Agent" and follow instructions.