. (Join-Path -Path $PSScriptRoot -ChildPath "..\ReadSettings\ReadSettings.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "Yaml.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "WriteSettings.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "GitHelper.Helper.ps1" -Resolve)

$workflowScheduleKey = "workflowSchedule"
$workflowTriggerKey = "workflowTrigger"
$workflowPRTriggerKey = "workflowPRTrigger"
$pipelineYamlPatchesKey = "pipelineYamlPatches"
# Central patches shipped with the BCDevOpsFlows scripts - applied to every repository that
# uses these scripts, before the repository's own pipelineYamlPatches setting
$pipelineYamlPatchesFilePath = Join-Path -Path $PSScriptRoot -ChildPath "..\CustomLogic\PipelineYamlPatches.json"
# Critical workflows may only run on allowed runners (windows-latest, or other specified in the template).
# Their runner and variables are not configurable and generic YAML patches never apply to them.
$criticalWorkflowNames = @('SetupPipelines')

function ConvertTo-YamlPathSegments {
    param (
        [Parameter(Mandatory = $true)]
        [string]$path
    )

    $segments = @()
    foreach ($rawSegment in $path.Split('.')) {
        if ($rawSegment -notmatch '^(?<key>[^\[\]]+)(?<indexPart>(\[\d+\])*)$') {
            throw "Invalid YAML path segment '$rawSegment' in path '$path'"
        }
        $indices = @()
        foreach ($indexMatch in [regex]::Matches($Matches.indexPart, '\[(\d+)\]')) {
            $indices += [int]$indexMatch.Groups[1].Value
        }
        $segments += , @{ key = $Matches.key; indices = $indices }
    }
    return , $segments
}

function Get-YamlValueByPath {
    param (
        [Parameter(Mandatory = $true)]
        $yamlContent,
        [Parameter(Mandatory = $true)]
        [string]$path
    )

    $current = $yamlContent
    foreach ($segment in (ConvertTo-YamlPathSegments -path $path)) {
        if ($current -isnot [System.Collections.IDictionary] -or -not $current.Contains($segment.key)) {
            return @{ found = $false; value = $null }
        }
        $current = $current[$segment.key]
        foreach ($index in $segment.indices) {
            if ($current -isnot [System.Collections.IList] -or $index -ge $current.Count) {
                return @{ found = $false; value = $null }
            }
            $current = $current[$index]
        }
    }
    return @{ found = $true; value = $current }
}

function Test-YamlValuesEqual {
    param (
        $first,
        $second
    )

    if ($null -eq $first -or $null -eq $second) {
        return ($null -eq $first) -and ($null -eq $second)
    }
    if ($first -is [System.Collections.IDictionary]) {
        if ($second -isnot [System.Collections.IDictionary] -or $first.Count -ne $second.Count) {
            return $false
        }
        foreach ($key in $first.Keys) {
            if (-not $second.Contains($key) -or -not (Test-YamlValuesEqual -first $first[$key] -second $second[$key])) {
                return $false
            }
        }
        return $true
    }
    if (($first -is [System.Collections.IList]) -and ($first -isnot [string])) {
        if ($second -isnot [System.Collections.IList] -or $second -is [string] -or $first.Count -ne $second.Count) {
            return $false
        }
        for ($i = 0; $i -lt $first.Count; $i++) {
            if (-not (Test-YamlValuesEqual -first $first[$i] -second $second[$i])) {
                return $false
            }
        }
        return $true
    }
    if ($second -is [System.Collections.IDictionary] -or (($second -is [System.Collections.IList]) -and ($second -isnot [string]))) {
        return $false
    }
    if ($first -is [bool] -and $second -is [bool]) {
        return $first -eq $second
    }
    return [string]::Equals("$first", "$second", [System.StringComparison]::Ordinal)
}

function Set-YamlValueByPath {
    param (
        [Parameter(Mandatory = $true)]
        $yamlContent,
        [Parameter(Mandatory = $true)]
        [string]$path,
        $value,
        [switch]$remove
    )

    $segments = ConvertTo-YamlPathSegments -path $path
    $lastSegment = $segments[-1]

    if ($remove) {
        if ($lastSegment.indices.Count -gt 0) {
            throw "Removing array elements is not supported (path '$path')"
        }
        $existing = Get-YamlValueByPath -yamlContent $yamlContent -path $path
        if (-not $existing.found) {
            return $false
        }
    }
    else {
        $existing = Get-YamlValueByPath -yamlContent $yamlContent -path $path
        if ($existing.found -and (Test-YamlValuesEqual -first $existing.value -second $value)) {
            return $false
        }
    }

    # Navigate to the container holding the last segment, creating missing intermediate maps
    $current = $yamlContent
    for ($i = 0; $i -lt $segments.Count - 1; $i++) {
        $segment = $segments[$i]
        if ($current -isnot [System.Collections.IDictionary]) {
            throw "Cannot navigate path '$path': segment '$($segment.key)' is not inside a map"
        }
        if (-not $current.Contains($segment.key) -or $null -eq $current[$segment.key]) {
            if ($segment.indices.Count -gt 0) {
                throw "Cannot navigate path '$path': array '$($segment.key)' does not exist"
            }
            $current[$segment.key] = [ordered]@{}
        }
        $current = $current[$segment.key]
        foreach ($index in $segment.indices) {
            if ($current -isnot [System.Collections.IList] -or $index -ge $current.Count) {
                throw "Cannot navigate path '$path': index [$index] on '$($segment.key)' is out of range"
            }
            $current = $current[$index]
        }
    }

    if ($current -isnot [System.Collections.IDictionary]) {
        throw "Cannot apply path '$path': parent of '$($lastSegment.key)' is not a map"
    }
    if ($remove) {
        $current.Remove($lastSegment.key)
        return $true
    }
    if ($lastSegment.indices.Count -eq 0) {
        $current[$lastSegment.key] = $value
        return $true
    }
    $target = $current[$lastSegment.key]
    for ($j = 0; $j -lt $lastSegment.indices.Count - 1; $j++) {
        $index = $lastSegment.indices[$j]
        if ($target -isnot [System.Collections.IList] -or $index -ge $target.Count) {
            throw "Cannot apply path '$path': index [$index] on '$($lastSegment.key)' is out of range"
        }
        $target = $target[$index]
    }
    $finalIndex = $lastSegment.indices[-1]
    if ($target -isnot [System.Collections.IList] -or $finalIndex -ge $target.Count) {
        throw "Cannot apply path '$path': index [$finalIndex] on '$($lastSegment.key)' is out of range"
    }
    $target[$finalIndex] = $value
    return $true
}

function ConvertTo-YamlCompatibleValue {
    param (
        $value
    )

    if ($value -is [PSCustomObject]) {
        $converted = [ordered]@{}
        foreach ($property in $value.PSObject.Properties) {
            $converted[$property.Name] = ConvertTo-YamlCompatibleValue -value $property.Value
        }
        return $converted
    }
    if (($value -is [System.Collections.IList]) -and ($value -isnot [string])) {
        $converted = @()
        foreach ($element in $value) {
            $converted += , (ConvertTo-YamlCompatibleValue -value $element)
        }
        return , $converted
    }
    return $value
}

function ConvertTo-PipelineYamlWorkflowPatches {
    param (
        [Parameter(Mandatory = $false)]
        [array]$patchDefinitions,
        [Parameter(Mandatory = $false)]
        [string]$workflowName,
        [Parameter(Mandatory = $true)]
        [string]$sourceDescription
    )

    $patches = @()
    foreach ($patchDefinition in $patchDefinitions) {
        if ($patchDefinition -is [PSCustomObject]) {
            $normalized = @{}
            foreach ($property in $patchDefinition.PSObject.Properties) {
                $normalized[$property.Name] = $property.Value
            }
            $patchDefinition = $normalized
        }
        # Use indexer access throughout: property access like .remove on a hashtable without
        # that key falls back to the .NET Remove method, which is truthy
        if ($patchDefinition -isnot [System.Collections.IDictionary] -or $patchDefinition.Keys -notcontains 'path' -or [string]::IsNullOrEmpty($patchDefinition['path'])) {
            throw "Each entry in $sourceDescription must be a structure containing a path property"
        }
        if (-not $patchDefinition['remove'] -and $patchDefinition.Keys -notcontains 'value') {
            throw "Each entry in $sourceDescription must contain either a value property or remove set to true (path '$($patchDefinition['path'])')"
        }
        $patchPipelineName = '*'
        if ($patchDefinition.Keys -contains 'pipeline' -and -not [string]::IsNullOrEmpty($patchDefinition['pipeline'])) {
            $patchPipelineName = $patchDefinition['pipeline']
        }
        if ("$workflowName" -notlike $patchPipelineName) {
            continue
        }
        if ($patchDefinition['remove']) {
            $patches += @{ path = $patchDefinition['path']; remove = $true }
        }
        else {
            $patches += @{ path = $patchDefinition['path']; value = (ConvertTo-YamlCompatibleValue -value $patchDefinition['value']) }
        }
    }
    # Emit the patches one by one; callers collect them with @(...)
    return $patches
}

function Get-PipelineYamlPatchesFromFile {
    param (
        [Parameter(Mandatory = $false)]
        [string]$workflowName
    )

    if (-not (Test-Path -Path $pipelineYamlPatchesFilePath -PathType Leaf)) {
        return @()
    }
    $fileContent = Get-Content -Path $pipelineYamlPatchesFilePath -Encoding UTF8 -Raw
    if ([string]::IsNullOrWhiteSpace($fileContent)) {
        return @()
    }
    try {
        $patchDefinitions = @($fileContent | ConvertFrom-Json)
    }
    catch {
        throw "Error reading $pipelineYamlPatchesFilePath. Error was $($_.Exception.Message)"
    }
    # Emit the patches one by one; callers collect them with @(...)
    return @(ConvertTo-PipelineYamlWorkflowPatches -patchDefinitions $patchDefinitions -workflowName $workflowName -sourceDescription $pipelineYamlPatchesFilePath)
}

function Get-PipelineYamlPatchesFromSettings {
    param (
        [Parameter(Mandatory = $false)]
        [string]$workflowName,
        [Parameter(Mandatory = $true)]
        [hashtable]$settings
    )

    $patches = @()

    # BCDevOpsFlows resource repository (applies to every workflow, including critical ones)
    if ($settings.Keys -notcontains 'BCDevOpsFlowsResourceRepositoryName' -or $settings.BCDevOpsFlowsResourceRepositoryName -eq '') {
        throw "The BCDevOpsFlowsResourceRepositoryName setting is required but was not provided."
    }
    if ($settings.Keys -notcontains 'BCDevOpsFlowsResourceRepositoryBranch' -or $settings.BCDevOpsFlowsResourceRepositoryBranch -eq '') {
        throw "The BCDevOpsFlowsResourceRepositoryBranch setting is required but was not provided."
    }
    if ($settings.Keys -notcontains 'BCDevOpsFlowsServiceConnectionName' -or $settings.BCDevOpsFlowsServiceConnectionName -eq '') {
        throw "The BCDevOpsFlowsServiceConnectionName setting is required but was not provided."
    }
    $patches += @{ path = 'resources.repositories[0].name'; value = $settings.BCDevOpsFlowsResourceRepositoryName }
    $patches += @{ path = 'resources.repositories[0].ref'; value = $settings.BCDevOpsFlowsResourceRepositoryBranch }
    $patches += @{ path = 'resources.repositories[0].endpoint'; value = $settings.BCDevOpsFlowsServiceConnectionName }

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
            $patches += @{ path = 'schedules'; value = $scheduledCronSettingsOrdered }
        }
        else {
            $patches += @{ path = 'schedules'; remove = $true }
        }

        # Add Change Trigger settings to the workflow
        if ($settings.Keys -contains $workflowTriggerKey) {
            if ($settings."$workflowTriggerKey" -isnot [hashtable]) {
                throw "The $workflowTriggerKey setting must be a structure"
            }
            $patches += @{ path = 'trigger'; value = $settings."$workflowTriggerKey" }
        }
        else {
            # Only neutralize an existing trigger; a workflow without a trigger key stays untouched
            $patches += @{ path = 'trigger'; value = 'none'; onlyIfPresent = $true }
        }
    }
    else {
        # Add PR Trigger settings to the workflow
        if ($settings.Keys -contains $workflowPRTriggerKey) {
            if ($settings."$workflowPRTriggerKey" -isnot [hashtable]) {
                throw "The $workflowPRTriggerKey setting must be a structure"
            }
            $patches += @{ path = 'pr'; value = $settings."$workflowPRTriggerKey" }
        }
        else {
            $patches += @{ path = 'pr'; value = 'none'; onlyIfPresent = $true }
        }
    }

    if ($criticalWorkflowNames -contains $workflowName) {
        return , $patches
    }

    # Override pool name based on workflow
    $newPoolName = switch ($workflowName) {
        'CICD' {
            if ($settings.Keys -contains 'BCDevOpsFlowsPoolNameCICD' -and $settings.BCDevOpsFlowsPoolNameCICD -ne '') {
                $settings.BCDevOpsFlowsPoolNameCICD
            }
        }
        'PublishToProduction' {
            if ($settings.Keys -contains 'BCDevOpsFlowsPoolNamePublishToProd' -and $settings.BCDevOpsFlowsPoolNamePublishToProd -ne '') {
                $settings.BCDevOpsFlowsPoolNamePublishToProd
            }
        }
    }
    if ($null -eq $newPoolName) {
        if ($settings.Keys -notcontains 'BCDevOpsFlowsPoolName' -or $settings.BCDevOpsFlowsPoolName -eq '') {
            throw "The BCDevOpsFlowsPoolName setting is required but was not provided."
        }
        $newPoolName = $settings.BCDevOpsFlowsPoolName
    }
    $patches += @{ path = 'pool.name'; value = $newPoolName }

    $variableGroups = @()
    if ($settings.Keys -contains 'BCDevOpsFlowsVariableGroups' -and $settings.BCDevOpsFlowsVariableGroups) {
        $variableGroups = @($settings.BCDevOpsFlowsVariableGroups)
    }

    # LEGACY, WILL BE REMOVED 2026/07 ->
    if ($settings.Keys -contains 'BCDevOpsFlowsVariableGroup' -and $settings.BCDevOpsFlowsVariableGroup -ne '') {
        if ($variableGroups -notcontains $settings.BCDevOpsFlowsVariableGroup) {
            $variableGroups += $settings.BCDevOpsFlowsVariableGroup
            Write-Warning "The BCDevOpsFlowsVariableGroup setting is deprecated and will be removed in July 2026. Please use BCDevOpsFlowsVariableGroups instead."
        }
        else {
            OutputDebug "BCDevOpsFlowsVariableGroup is defined but already included in BCDevOpsFlowsVariableGroups, skipping..."
        }
    }
    # LEGACY, WILL BE REMOVED 2026/07 <-

    if ($variableGroups.Count -eq 0) {
        throw "The BCDevOpsFlowsVariableGroups setting is required but was not provided."
    }

    $variableGroupValues = @()
    foreach ($group in $variableGroups) {
        $variableGroupValues += @{ group = $group }
    }
    $patches += @{ path = 'variables'; value = $variableGroupValues }

    # Generic patches (never applied to critical workflows): central patches shipped with the
    # BCDevOpsFlows scripts first, then repository-specific patches from settings so they win
    $patches += @(Get-PipelineYamlPatchesFromFile -workflowName $workflowName)
    if ($settings.Keys -contains $pipelineYamlPatchesKey -and $settings."$pipelineYamlPatchesKey") {
        $patches += @(ConvertTo-PipelineYamlWorkflowPatches -patchDefinitions @($settings."$pipelineYamlPatchesKey") -workflowName $workflowName -sourceDescription "the $pipelineYamlPatchesKey setting")
    }

    return , $patches
}

function Update-PipelineYamlContentFromPatches {
    param (
        [Parameter(Mandatory = $true)]
        $yamlContent,
        [Parameter(Mandatory = $true)]
        [array]$patches
    )

    $changed = $false
    foreach ($patch in $patches) {
        # Use indexer access throughout: property access like .remove on a hashtable without
        # that key falls back to the .NET Remove method, which is truthy
        if ($patch['remove']) {
            if (Set-YamlValueByPath -yamlContent $yamlContent -path $patch['path'] -remove) {
                OutputDebug "Removed '$($patch['path'])' from workflow"
                $changed = $true
            }
            continue
        }
        if ($patch['onlyIfPresent']) {
            $existing = Get-YamlValueByPath -yamlContent $yamlContent -path $patch['path']
            if (-not $existing.found -or -not $existing.value) {
                continue
            }
        }
        if (Set-YamlValueByPath -yamlContent $yamlContent -path $patch['path'] -value $patch['value']) {
            OutputDebug "Set '$($patch['path'])' in workflow"
            $changed = $true
        }
    }
    return $changed
}

function Update-PipelineYMLFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$filePath,
        [switch]$skipVariableNameReplacement
    )

    # Get Yaml content and workflow name
    $yamlContent = Get-AsYamlFromFile -FileName $filePath
    $workflowName = $yamlContent.jobs[0].variables.AL_PIPELINENAME

    # Read settings including workflow specific settings + setup pipeline settings
    $settings = ReadSettings -pipelineName $workflowName -setupPipelineName "$ENV:AL_PIPELINENAME" -userReqForEmail '' -branchName '' | ConvertTo-HashTable -recurse

    $patches = Get-PipelineYamlPatchesFromSettings -workflowName $workflowName -settings $settings
    $changed = Update-PipelineYamlContentFromPatches -yamlContent $yamlContent -patches $patches
    if ($changed) {
        Write-Yaml -FileName $filePath -Content $yamlContent
    }

    if (-not $skipVariableNameReplacement) {
        $changed = (ReplaceVariableNamesInWorkflow -filePath $filePath -workflowName $workflowName -settings $settings) -or $changed
    }
    return $changed
}

function Update-PipelineYMLFiles {
    param (
        [Parameter(Mandatory = $true)]
        [string]$templateFolderPath,
        [Parameter(Mandatory = $true)]
        [string]$pipelineFolderPath
    )

    $anyChanged = $false
    $ymlFiles = Get-ChildItem -Path $pipelineFolderPath -Filter "*.yml" -File
    foreach ($pipelineFile in $ymlFiles) {
        $changed = Update-PipelineYMLFile -filePath $pipelineFile.FullName
        $anyChanged = $changed -or $anyChanged

        # Keep the template converged so the next SetupPipelines restore does not undo the change.
        # Variable name replacement must never run on templates: SetupPipelines relies on templates
        # keeping the default variable names to be able to apply a rename after restore.
        $templateFile = Join-Path -Path $templateFolderPath -ChildPath $pipelineFile.Name
        if (Test-Path -Path $templateFile -PathType Leaf) {
            $changed = Update-PipelineYMLFile -filePath $templateFile -skipVariableNameReplacement
            $anyChanged = $changed -or $anyChanged
        }
    }
    return $anyChanged
}

function ReplaceVariableNamesInWorkflow {
    param (
        [Parameter(Mandatory = $true)]
        [string]$filePath,
        [Parameter(Mandatory = $false)]
        [string]$workflowName,
        [Parameter(Mandatory = $true)]
        [hashtable] $settings
    )

    $defaultAuthContextVar = 'AL_AUTHCONTEXT'
    $defaultTrustedNuGetVar = 'AL_TRUSTEDNUGETFEEDS'
    if ($settings.Keys -notcontains 'BCDevOpsFlowsAuthContextVarName' -or $settings.BCDevOpsFlowsAuthContextVarName -eq '') {
        throw "The BCDevOpsFlowsAuthContextVarName setting is required but was not provided."
    }
    if ($settings.Keys -notcontains 'BCDevOpsFlowsTrustedNuGetFeedVarName' -or $settings.BCDevOpsFlowsTrustedNuGetFeedVarName -eq '') {
        throw "The BCDevOpsFlowsTrustedNuGetFeedVarName setting is required but was not provided."
    }

    $originalYamlText = Get-Content -Path $filePath -Raw
    $yamlText = $originalYamlText
    $configuredVariableName = $settings.BCDevOpsFlowsAuthContextVarName
    if ($configuredVariableName -ne $defaultAuthContextVar) {
        $existingVariableName = '$(' + $defaultAuthContextVar + ')'
        $newVariableName = '$(' + $configuredVariableName + ')'
        $yamlText = $yamlText -replace [regex]::Escape($existingVariableName), $newVariableName
        $existingVariableName = 'variables[''' + $defaultAuthContextVar + ''']'
        $newVariableName = 'variables[''' + $configuredVariableName + ''']'
        $yamlText = $yamlText -replace [regex]::Escape($existingVariableName), $newVariableName
        OutputDebug "Replaced $defaultAuthContextVar with $configuredVariableName in workflow $workflowName"
    }

    $configuredVariableName = $settings.BCDevOpsFlowsTrustedNuGetFeedVarName
    if ($configuredVariableName -ne $defaultTrustedNuGetVar) {
        $existingVariableName = '$(' + $defaultTrustedNuGetVar + ')'
        $newVariableName = '$(' + $configuredVariableName + ')'
        $yamlText = $yamlText -replace [regex]::Escape($existingVariableName), $newVariableName
        $existingVariableName = 'variables[''' + $defaultTrustedNuGetVar + ''']'
        $newVariableName = 'variables[''' + $configuredVariableName + ''']'
        $yamlText = $yamlText -replace [regex]::Escape($existingVariableName), $newVariableName
        OutputDebug "Replaced $defaultTrustedNuGetVar with $configuredVariableName in workflow $workflowName"
    }

    if ($yamlText -ne $originalYamlText) {
        Set-ContentLF -Path $filePath -Content $yamlText
        OutputDebug "Updated variable names in workflow file: $filePath"
        return $true
    }
    return $false
}

function Invoke-PipelineYamlSelfHeal {
    Param()

    # Never heal from a pull request build: the checkout is a transient merge commit and any push
    # would either target a non-writable ref or complete the merge outside the PR process.
    if ($ENV:BUILD_REASON -eq 'PullRequest') {
        OutputDebug "Skipping pipeline YAML self-healing for pull request build"
        return
    }
    # SetupPipelines performs the full template restore + update itself
    if ($criticalWorkflowNames -contains "$ENV:AL_PIPELINENAME") {
        OutputDebug "Skipping pipeline YAML self-healing for critical workflow $ENV:AL_PIPELINENAME"
        return
    }
    $pipelineFolder = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath $scriptsFolderName
    $templateFolder = Join-Path -Path $pipelineFolder -ChildPath 'Templates'
    if (-not (Test-Path -Path (Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath $repoSettingsFile) -PathType Leaf)) {
        OutputDebug "Skipping pipeline YAML self-healing - no repository settings file found"
        return
    }
    if (-not (Test-Path -Path $pipelineFolder -PathType Container) -or -not (Get-ChildItem -Path $pipelineFolder -Filter *.yml -File)) {
        OutputDebug "Skipping pipeline YAML self-healing - no pipeline YAML files found in $pipelineFolder"
        return
    }

    # Read with the same parameters SetupPipelines uses so healed content is identical to setup output
    $settings = ReadSettings -pipelineName "$ENV:AL_PIPELINENAME" -userReqForEmail '' -branchName '' | ConvertTo-HashTable -recurse
    if (-not $settings.pipelineSelfHealing) {
        OutputDebug "Skipping pipeline YAML self-healing - pipelineSelfHealing is not enabled"
        return
    }
    if ([string]::IsNullOrEmpty($settings.pipelineBranch)) {
        OutputDebug "Skipping pipeline YAML self-healing - settings.pipelineBranch is not set"
        return
    }
    # Heal commits originate only on the pipeline branch; they reach test branches through the
    # existing main -> test/preview push propagation. Healing other branches would make them
    # diverge and break that fast-forward propagation.
    $branchName = "$ENV:BUILD_SOURCEBRANCH" -replace '^refs/heads/', ''
    if ($branchName -ne $settings.pipelineBranch) {
        OutputDebug "Skipping pipeline YAML self-healing - branch $branchName is not the pipeline branch $($settings.pipelineBranch)"
        return
    }

    Push-Location $ENV:BUILD_REPOSITORY_LOCALPATH
    try {
        Set-GitUser
        $changed = Update-PipelineYMLFiles -templateFolderPath $templateFolder -pipelineFolderPath $pipelineFolder
        if (-not $changed) {
            Write-Host "Pipeline YAML files match settings - no self-healing needed"
            return
        }
        Write-Host "Pipeline YAML drift detected - self-healing pipeline files from settings"
        Invoke-GitAddCommit -appFolderPath $pipelineFolder -commitMessage "Self-heal BCDevOpsFlows pipeline files from settings"
        Invoke-GitPush -targetBranch "HEAD:$($settings.pipelineBranch)"
    }
    finally {
        Pop-Location
    }
}
