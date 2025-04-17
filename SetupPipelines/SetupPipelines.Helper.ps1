. (Join-Path -Path $PSScriptRoot -ChildPath "..\ReadSettings\ReadSettings.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Yaml.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteSettings.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

$workflowScheduleKey = "workflowSchedule"
$workflowTriggerKey = "workflowTrigger"

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
            throw "Invalid settings.pipelineFolderStructure: $($settings.pipelineFolderStructure)"
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

    OutputDebug "Preparing pipeline '$pipelineName' for branch '$pipelineBranch' with YAML file '$pipelineYamlFileRelativePath' in folder '$pipelineFolder'"
    if ($skipPipelineFirstRun) {
        OutputDebug "Setting skip first run of pipeline '$pipelineName'"
    }

    $existingPipelineDetails = az pipelines list `
        --name "$pipelineName" `
        --folder-path "$pipelineFolder" `
        --organization "$ENV:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI" `
        --project "$ENV:SYSTEM_TEAMPROJECT" `
        --repository "$ENV:BUILD_REPOSITORY_NAME" `
        --repository-type "tfsgit" | ConvertFrom-Json
        
    OutputDebug "Existing pipeline details: $existingPipelineDetails"
    if ($existingPipelineDetails.Count -gt 0) {
        Write-Host "Pipeline $pipelineName in folder $pipelineFolder already exists. Skipping creation."
        return
    }

    Write-Host "Creating pipeline $pipelineName in folder $pipelineFolder"
    az pipelines create `
        --name "$pipelineName" `
        --folder-path "$pipelineFolder" `
        --organization "$ENV:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI" `
        --project "$ENV:SYSTEM_TEAMPROJECT" `
        --description "Pipeline $pipelineName created by SetupPipelines." `
        --repository "$ENV:BUILD_REPOSITORY_NAME" `
        --branch $pipelineBranch `
        --yml-path "$pipelineYamlFileRelativePath" `
        --repository-type "tfsgit" `
        --skip-first-run $skipPipelineFirstRun
}

function Copy-PipelineTemplateFilesToPipelineFolder {
    param (
        [Parameter(Mandatory = $true)]
        [string]$templateFolderPath,
        [Parameter(Mandatory = $true)]
        [string]$targetPipelineFolderPath
    )

    if (-not (Test-Path -Path $templateFolderPath -PathType Container)) {
        throw "Pipeline Template folder does not exist: $templateFolderPath"
    }
    if (-not (Test-Path -Path $targetPipelineFolderPath -PathType Container)) {
        throw "Target Pipeline folder does not exist: $targetPipelineFolderPath"
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
        [string]$pipelineFolderPath
    )

    $ymlFiles = Get-ChildItem -Path $templateFolderPath -Filter "*.yml" -File
    foreach ($templateFile in $ymlFiles) {
        $pipelineFile = Join-Path -Path $pipelineFolderPath -ChildPath $templateFile.Name
        if (-not (Test-Path -Path $pipelineFile)) {
            throw "Pipeline YML file does not exist: $pipelineFile"
            continue
        }
        Update-PipelineYMLFile -filePath $pipelineFile
    }
}

function Update-PipelineYMLFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$filePath
    )
    
    # Read settings without workflow specific settings
    $settings = ReadSettings -pipelineName '' -setupPipelineName '' -userReqForEmail '' -branchName '' | ConvertTo-HashTable -recurse

    $yamlContent = Get-AsYamlFromFile -FileName $filePath
    $workflowName = $yamlContent.jobs[0].variables.AL_PIPELINENAME
    foreach ($key in @($workflowScheduleKey, $workflowTriggerKey)) {
        if ($settings.Keys -contains $key -and ($settings."$key")) {
            throw "The $key setting is not allowed in the global repository settings. Please use the workflow specific settings file or conditional settings."
        }
    }

    # Re-read settings and this time include workflow specific settings + setup pipeline settings
    $settings = ReadSettings -pipelineName $workflowName -setupPipelineName "$ENV:AL_PIPELINENAME" -userReqForEmail '' -branchName '' | ConvertTo-HashTable -recurse

    # Any workflow (except for the Pull_Request) can have concurrency and schedule defined
    if ($workflowName -ne "PullRequest") {
        # Add Schedule settings to the workflow
        if ($settings.Keys -contains $workflowScheduleKey) {
            $scheduledCronSettings = $settings."$workflowScheduleKey"
            if ($scheduledCronSettings -isnot [array]) {
                $scheduledCronSettings = @($scheduledCronSettings)
            }
            $scheduledCronSettingsOrdered = @()
            foreach ($schedule in $scheduledCronSettings) {
                if ($schedule -isnot [hashtable] -or $schedule.Keys -notcontains 'cron' -or $schedule.cron -isnot [string]) {
                    throw "Each schedule in $workflowScheduleKey must be a structure containing a cron property"
                }
                OutputDebug "Schedule cron: $($schedule.cron)"
                $orderedSchedule = [ordered]@{}
                # Add cron first
                if ($schedule.ContainsKey('cron')) {
                    $orderedSchedule['cron'] = $schedule.cron
                }
                # Add remaining properties
                foreach ($key in $schedule.Keys) {
                    if ($key -ne 'cron') {
                        $orderedSchedule[$key] = $schedule[$key]
                    }
                }
                $scheduledCronSettingsOrdered += $orderedSchedule
            }
            # Add Workflow Schedule to the workflow
            $yamlContent.schedules = $scheduledCronSettingsOrdered
            OutputDebug "Adding schedule to workflow: $scheduledCronSettingsOrdered"
        }
        elseif ($yamlContent.schedules) {
            $yamlContent.Remove('schedules')
            OutputDebug "Removing schedule from workflow"
        }

        # Add Change Trigger settings to the workflow
        if ($settings.Keys -contains $workflowTriggerKey) {
            if ($settings."$workflowTriggerKey" -isnot [hashtable]) {
                throw "The $workflowTriggerKey setting must be a structure"
            }
            # Add Workflow Schedule to the workflow
            $yamlContent.trigger = $($settings."$workflowTriggerKey")
            OutputDebug "Adding trigger to workflow: $($settings."$workflowTriggerKey")"
        }
        elseif ($yamlContent.trigger -and $yamlContent.trigger -ne 'none') {
            $yamlContent.trigger = 'none'
            OutputDebug "Removing schedule from workflow"
        }
    }
    
    $yamlContent = ModifyBCDevOpsFlowsInWorkflows -yamlContent $yamlContent -settings $settings
    # Critical workflows may only run on allowed runners (windows-latest, or other specified in the template. This runner is not configurable)
    $criticalWorkflows = @('SetupPipelines')
    if ($criticalWorkflows -notcontains $workflowName) {
        $yamlContent = ModifyRunnersAndVariablesInWorkflows -yamlContent $yamlContent -settings $settings
    }

    Write-Yaml -FileName $filePath -Content $yamlContent
}

function ModifyBCDevOpsFlowsInWorkflows {
    Param(
        $yamlContent,
        [hashtable] $settings
    )

    if ($settings.Keys -notcontains 'BCDevOpsFlowsResourceRepositoryName' -or $settings.BCDevOpsFlowsResourceRepositoryName -eq '') {
        throw "The BCDevOpsFlowsResourceRepositoryName setting is required but was not provided."
    }
    $yamlContent.resources.repositories[0].name = $settings.BCDevOpsFlowsResourceRepositoryName
    if ($settings.Keys -notcontains 'BCDevOpsFlowsResourceRepositoryBranch' -or $settings.BCDevOpsFlowsResourceRepositoryBranch -eq '') {
        throw "The BCDevOpsFlowsResourceRepositoryBranch setting is required but was not provided."
    }
    $yamlContent.resources.repositories[0].ref = $settings.BCDevOpsFlowsResourceRepositoryBranch
    if ($settings.Keys -notcontains 'BCDevOpsFlowsServiceConnectionName' -or $settings.BCDevOpsFlowsServiceConnectionName -eq '') {
        throw "The BCDevOpsFlowsServiceConnectionName setting is required but was not provided."
    }
    $yamlContent.resources.repositories[0].endpoint = $settings.BCDevOpsFlowsServiceConnectionName
    return $yamlContent
}

function ModifyRunnersAndVariablesInWorkflows {
    Param(
        $yamlContent,
        [hashtable] $settings
    )

    if ($settings.Keys -notcontains 'BCDevOpsFlowsPoolName' -or $settings.BCDevOpsFlowsPoolName -eq '') {
        throw "The BCDevOpsFlowsPoolName setting is required but was not provided."
    }
    $yamlContent.pool.name = $settings.BCDevOpsFlowsPoolName
    if ($settings.Keys -notcontains 'BCDevOpsFlowsVariableGroup' -or $settings.BCDevOpsFlowsVariableGroup -eq '') {
        throw "The BCDevOpsFlowsVariableGroup setting is required but was not provided."
    }
    $yamlContent.variables[0].group = $settings.BCDevOpsFlowsVariableGroup
    return $yamlContent
}
    