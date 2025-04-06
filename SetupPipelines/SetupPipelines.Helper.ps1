. (Join-Path -Path $PSScriptRoot -ChildPath "..\ReadSettings\ReadSettings.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Yaml.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteSettings.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

$workflowScheduleKey = "WorkflowSchedule"
$CICDPushBranchesKey = "CICDPushBranches"

function Get-PipelineDevOpsFolderPath {
    Param(
        [Parameter(Mandatory = $true)]
        $settings
    )

    switch ($settings.pipelineFolderStructure) {
        'Repository' {
            $pipelineFolderPath = $ENV:BUILD_REPOSITORY_NAME
        }
        'Pipeline' {
            $pipelineFolderPath = $ENV:BUILD_DEFINITIONNAME
        }
        'Path' {
            $pipelineFolderPath = $settings.pipelineFolderPath
        }
        '' { 
            $pipelineFolderPath = ''
        }
        default { 
            Write-Error "Invalid settings.pipelineFolderStructure: $($settings.pipelineFolderStructure)"
        }
    }
    if ($pipelineFolderPath -eq '') {
        $pipelineFolderPath = '\'
    }
    OutputDebug "Using pipeline folder path: $pipelineFolderPath for $($settings.pipelineFolderStructure)"
    return $pipelineFolderPath
}

function Install-AzureCLIDevOpsExtension {
    Param()

    OutputDebug "Adding Azure DevOps extension to Azure CLI"
    az extension add -n azure-devops
}

function Add-AzureDevOpsPipelineFromYaml {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $pipelineName,
        [Parameter(Mandatory = $true)]
        [string] $pipelineFolder,
        [Parameter(Mandatory = $true)]
        [string] $pipelineBranch,
        [Parameter(Mandatory = $true)]
        [string] $pipelineYamlFileRelativePath,
        [Parameter(Mandatory = $false)]
        [bool] $skipPipelineFirstRun = $false
    )

    OutputDebug "Creating pipeline '$pipelineName' for branch '$pipelineBranch' with YAML file '$pipelineYamlFileRelativePath' in folder '$pipelineFolder'"
    if ($skipPipelineFirstRun) {
        OutputDebug "Skipping first run of pipeline '$pipelineName'"
    }

    # az pipelines create `
    #     --name "$pipelineName" `
    #     --folder-path "$pipelineFolder" `
    #     --organization "$ENV:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI" `
    #     --project "$ENV:SYSTEM_TEAMPROJECT" `
    #     --description "Pipeline $pipelineName created by SetupPipelines." `
    #     --repository "$ENV:BUILD_REPOSITORY_NAME" `
    #     --branch $pipelineBranch `
    #     --yml-path "$pipelineYamlFileRelativePath" `
    #     --repository-type "tfsgit" `
    #     --skip-first-run $skipPipelineFirstRun
}

function Copy-PipelineTemplateFilesToPipelineFolder {
    param (
        [Parameter(Mandatory = $true)]
        [string]$templateFolderPath,
        [Parameter(Mandatory = $true)]
        [string]$targetPipelineFolderPath
    )

    if (-not (Test-Path -Path $templateFolderPath -PathType Container)) {
        Write-Error "Pipeline Template folder does not exist: $templateFolderPath"
    }
    if (-not (Test-Path -Path $targetPipelineFolderPath -PathType Container)) {
        Write-Error "Target Pipeline folder does not exist: $targetPipelineFolderPath"
    }

    OutputDebug "Copying files from template folder '$templateFolderPath' to '$targetPipelineFolderPath'"
    $templateFiles = Get-ChildItem -Path $templateFolderPath -File -Recurse -Include *.json, *.yml
    foreach ($file in $templateFiles) {
        $targetFile = Join-Path -Path $targetPipelineFolderPath -ChildPath $file.Name
        if (Test-Path -Path $targetFile) {
            if ($file.Extension -eq '.yml') {
                OutputDebug "Restoring pipeline from template $($file.Name)"
                Copy-Item -Path $file.FullName -Destination $targetFile -Force
            }
            elseif ($file.Extension -eq '.json') {
                OutputDebug "JSON file $($file.Name) already exists, skipping copy"
            }
        }
        else {
            OutputDebug "Creating new file from template: $($file.Name)"
            Copy-Item -Path $file.FullName -Destination $targetFile -Force
        }
    }
}

function Update-PipelineYMLFiles {
    param (
        [Parameter(Mandatory = $true)]
        [string]$templateFolderPath,
        [Parameter(Mandatory = $true)]
        [string]$pipelineFolderPath,
        [Parameter(Mandatory = $true)]
        [hashtable] $settings
    )

    $ymlFiles = Get-ChildItem -Path $templateFolderPath -Filter "*.yml" -File
    foreach ($templateFile in $ymlFiles) {
        $pipelineFile = Join-Path -Path $pipelineFolderPath -ChildPath $templateFile.Name
        if (-not (Test-Path -Path $pipelineFile)) {
            Write-Error "Pipeline YML file does not exist: $pipelineFile"
            continue
        }
        Update-PipelineYMLFile -filePath $pipelineFile -settings $settings
    }
}

function Update-PipelineYMLFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$filePath,
        [Parameter(Mandatory = $true)]
        [hashtable] $settings
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
    $yamlContent = Get-AsYamlFromFile -FileName $filePath
    $workflowName = $yamlContent.jobs[0].variables.AL_PIPELINENAME
    foreach ($key in @($workflowScheduleKey)) {
        if ($settings.Keys -contains $key -and ($settings."$key")) {
            throw "The $key setting is not allowed in the global repository settings. Please use the workflow specific settings file or conditional settings."
        }
    }

    # Re-read settings and this time include workflow specific settings
    $settings = ReadSettings -workflowName $workflowName -userReqForEmail '' -branchName '' | ConvertTo-HashTable -recurse

    # Any workflow (except for the Pull_Request) can have concurrency and schedule defined
    if ($baseName -ne "Pull_Request") {
        # Add Schedule settings to the workflow
        if ($settings.Keys -contains $workflowScheduleKey) {
            if ($settings."$workflowScheduleKey" -isnot [hashtable] -or $settings."$workflowScheduleKey".Keys -notcontains 'cron' -or $settings."$workflowScheduleKey".cron -isnot [string]) {
                throw "The $workflowScheduleKey setting must be a structure containing a cron property"
            }
            # Replace or add the schedule part under the on: key
            # TODO $yamlContent.ReplaceOrAdd('on:/', 'schedule:', @("- cron: '$($settings."$workflowScheduleKey".cron)'"))
        }
    }
    
    $yamlContent = ModifyAllWorkflows -yamlContent $yamlContent -settings $settings
    if ($baseName -eq "CICD") {
        $yamlContent = ModifyCICDWorkflow -yamlContent $yamlContent -settings $settings
    }
    if ($baseName -eq "Publish_To_Production") {
        # TODO $yamlContent = ModifyPublishToProductionWorkflow -yaml $yamlContent -repoSettings $settings
    }
    
    $criticalWorkflows = @('UpdateGitHubGoSystemFiles', 'Troubleshooting')
    $allowedRunners = @('windows-latest', 'ubuntu-latest')
    $modifyRunsOnAndShell = $true
    
    # Critical workflows may only run on allowed runners (must always be able to run)
    if ($criticalWorkflows -contains $baseName) {
        if ($allowedRunners -notcontains $settings."runs-on") {
            $modifyRunsOnAndShell = $false
        }
    }
    
    if ($modifyRunsOnAndShell) {
        # TODO $yamlContent = ModifyRunsOnAndShell -yaml $yamlContent -repoSettings $settings
    }
    
    # PullRequestHandler, CICD, Current, NextMinor and NextMajor workflows all include a build step.
    # If the dependency depth is higher than 1, we need to add multiple dependent build jobs to the workflow
    if ($baseName -eq 'PullRequestHandler' -or $baseName -eq 'CICD' -or $baseName -eq 'Current' -or $baseName -eq 'NextMinor' -or $baseName -eq 'NextMajor') {
        # TODO $yamlContent = ModifyBuildWorkflows -yaml $yamlContent -depth $depth -includeBuildPP $includeBuildPP
    }
    
    if ($baseName -eq 'UpdateGitHubGoSystemFiles') {
        # TODO $yamlContent = ModifyUpdateALGoSystemFiles -yaml $yamlContent -repoSettings $settings
    }

    Write-Yaml -FileName $filePath -Content $yamlContent
}

function ModifyAllWorkflows {
    Param(
        $yamlContent,
        [hashtable] $settings
    )

    # BCDevOpsFlows Repository name is needed in all workflows to specify the repository name
    if ($settings.Keys -notcontains 'BCDevOpsFlowsResourceRepositoryName' -or $settings.BCDevOpsFlowsResourceRepositoryName -eq '') {
        Write-Error "The resourceRepositoryName setting is required but was not provided."
    }
    $yamlContent.resources.repositories[0].name = $settings.BCDevOpsFlowsResourceRepositoryName

    # BCDevOpsFlows Service Connection name is needed in all workflows to specify the service connection name
    if ($settings.Keys -notcontains 'BCDevOpsFlowsServiceConnectionName' -or $settings.BCDevOpsFlowsServiceConnectionName -eq '') {
        Write-Error "The serviceConnectionName setting is required but was not provided."
    }
    $yamlContent.resources.repositories[0].endpoint = $settings.BCDevOpsFlowsServiceConnectionName

    # Pool Name is needed in all workflows to specify the agent pool
    if ($settings.Keys -notcontains 'devOpsPoolName' -or $settings.devOpsPoolName -eq '') {
        Write-Error "The devOpsPoolName setting is required but was not provided."
    }
    $yamlContent.pool.name = $settings.devOpsPoolName

    # Variable Group Name is needed in all workflows to specify the variable group name
    if ($settings.Keys -notcontains 'devOpsVariableGroup' -or $settings.devOpsVariableGroup -eq '') {
        Write-Error "The devOpsVariableGroup setting is required but was not provided."
    }
    $yamlContent.variables[0].group = $settings.devOpsVariableGroup
    return $yamlContent
}

function ModifyCICDWorkflow {
    Param(
        $yamlContent,
        [hashtable] $settings
    )

    if ($repoSettings.Keys -contains $CICDPushBranchesKey) {
        $CICDPushBranches = $repoSettings.CICDPushBranches
    }
    elseif ($repoSettings.Keys -contains $workflowScheduleKey) {
        $CICDPushBranches = ''
    }
    if ($CICDPushBranches) {
        $yamlContent.trigger = @{
            "branches" = @{
                "include" = @($settings.CICDPushBranches -join ',')
            }
        }
    }
    else {
        $yamlContent.trigger = 'none'
    }
    return $yamlContent
}