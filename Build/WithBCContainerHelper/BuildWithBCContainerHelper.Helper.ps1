function GetContainerName() {
    "bc-$($ENV:BUILD_REPOSITORY_NAME -replace "[^a-z0-9]")-$($ENV:BUILD_BUILDID -replace "[^a-z0-9]")"
}

function Move-CustomCodeCopsToBaseFolder {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $settings,
        [Parameter(Mandatory = $true)]
        [string] $baseFolder
    )

    if (-not $settings.customCodeCops -or $settings.customCodeCops.Count -eq 0) {
        return $settings
    }

    $normalizedBaseFolder = [System.IO.Path]::GetFullPath($baseFolder)
    $stagedFolder = Join-Path $normalizedBaseFolder ".buildartifacts\CustomCodeCops"
    $stagedCustomCodeCops = @()
    $stagedCount = 0

    foreach ($customCodeCop in $settings.customCodeCops) {
        if ([string]::IsNullOrWhiteSpace($customCodeCop) -or $customCodeCop -like 'https://*') {
            $stagedCustomCodeCops += $customCodeCop
            continue
        }
        if ($customCodeCop -like 'http://*') {
            throw "Custom code cop URL must use HTTPS. Insecure HTTP URL is not allowed: $customCodeCop"
        }

        $sourcePath = [System.IO.Path]::GetFullPath($customCodeCop)
        if ($sourcePath.StartsWith($normalizedBaseFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
            $stagedCustomCodeCops += $sourcePath
            continue
        }

        if (-not (Test-Path -Path $sourcePath -PathType Leaf)) {
            throw "The customCodeCop file does not exist: $sourcePath"
        }

        if (-not (Test-Path -Path $stagedFolder)) {
            New-Item -Path $stagedFolder -ItemType Directory | Out-Null
        }

        $stagedCount++
        $targetPath = Join-Path $stagedFolder (Split-Path $sourcePath -Leaf)
        Copy-Item -Path $sourcePath -Destination $targetPath -Force
        Write-Host "Staged customCodeCop to $targetPath"
        $stagedCustomCodeCops += $targetPath
    }

    $settings.customCodeCops = $stagedCustomCodeCops
    return $settings
}

function Resolve-RulesetIncludes {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $filePath,
        [Parameter(Mandatory = $true)]
        [string] $hostStagingFolder,
        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.HashSet[string]] $resolvedUrls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    )

    $rulesetContent = Get-Content -Path $filePath -Raw | ConvertFrom-Json
    $rulesetDir = Split-Path -Path $filePath -Parent
    $hasChanges = $false

    if ($rulesetContent.includedRuleSets) {
        for ($i = 0; $i -lt $rulesetContent.includedRuleSets.Count; $i++) {
            $entry = $rulesetContent.includedRuleSets[$i]
            $entryPath = $entry.path

            if ($entryPath -like 'http://*') {
                throw "Ruleset 'includedRuleSets' path must use HTTPS. Insecure HTTP URL is not allowed: $entryPath"
            }

            if ($entryPath -like 'https://*') {
                $fileName = [System.Uri]::new($entryPath).Segments[-1]
                $hostDestinationFile = Join-Path $hostStagingFolder $fileName

                if (-not $resolvedUrls.Contains($entryPath)) {
                    $resolvedUrls.Add($entryPath) | Out-Null
                    OutputDebug -Message "Downloading external ruleset include: $entryPath -> $hostDestinationFile"
                    Download-File -SourceUrl $entryPath -destinationFile $hostDestinationFile
                    Resolve-RulesetIncludes -filePath $hostDestinationFile -hostStagingFolder $hostStagingFolder -resolvedUrls $resolvedUrls | Out-Null
                }

                $entry.path = Join-Path $hostStagingFolder $fileName
                $hasChanges = $true
            }
            else {
                # Local path: when creating a staging copy, convert relative paths to absolute
                # so they remain resolvable from the staging folder's different location.
                # These are repo-local files accessible to the container via baseFolder mount.
                if (-not [System.IO.Path]::IsPathRooted($entryPath)) {
                    $absolutePath = [System.IO.Path]::GetFullPath((Join-Path $rulesetDir $entryPath))
                    $entry.path = $absolutePath
                    $hasChanges = $true
                }
            }
        }
    }

    if ($hasChanges) {
        $outputPath = Join-Path $hostStagingFolder (Split-Path $filePath -Leaf)
        $rulesetContent | ConvertTo-Json -Depth 10 | Set-Content -Path $outputPath -Encoding UTF8
        OutputDebug -Message "Staged ruleset with resolved includes: $outputPath"
        return $outputPath
    }

    return $filePath
}

function Resolve-ExternalRulesetFiles {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $settings,
        [Parameter(Mandatory = $true)]
        [string] $baseFolder
    )

    if (-not $settings.enableExternalRulesets) {
        return $settings
    }
    if ([string]::IsNullOrWhiteSpace($settings.rulesetFile)) {
        return $settings
    }

    $rulesetValue = $settings.rulesetFile

    if ($rulesetValue -like 'http://*') {
        throw "Ruleset file URL must use HTTPS. Insecure HTTP URL is not allowed: $rulesetValue"
    }

    $hostStagingFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder 'ExternalRulesets'
    if (-not (Test-Path $hostStagingFolder)) {
        New-Item -Path $hostStagingFolder -ItemType Directory | Out-Null
    }

    if ($rulesetValue -like 'https://*') {
        # External URL: download the ruleset file itself first, then process its includes
        $fileName = [System.Uri]::new($rulesetValue).Segments[-1]
        $rulesetFilePath = Join-Path $hostStagingFolder $fileName
        OutputDebug -Message "Downloading external ruleset file: $rulesetValue -> $rulesetFilePath"
        Download-File -SourceUrl $rulesetValue -destinationFile $rulesetFilePath
    }
    else {
        # Local path: don't download the file itself, but process its includes
        $rulesetFilePath = [System.IO.Path]::GetFullPath((Join-Path $baseFolder $rulesetValue))
        if (-not (Test-Path $rulesetFilePath)) {
            throw "The specified ruleset file does not exist: $rulesetFilePath. Please verify that the 'rulesetFile' setting is correct."
        }
    }

    $resolvedHostPath = Resolve-RulesetIncludes -filePath $rulesetFilePath -hostStagingFolder $hostStagingFolder

    if ($resolvedHostPath -ne $rulesetFilePath) {
        # A staging copy with modified includes was created;
        $newRulesetPath = Join-Path $hostStagingFolder (Split-Path $resolvedHostPath -Leaf)
        Write-Host "Ruleset staged to BCC shared folder ($resolvedHostPath)"
        $settings.rulesetFile = $newRulesetPath
    }
    elseif ($rulesetValue -like 'https://*') {
        # Downloaded external ruleset with no include changes;
        $newRulesetPath = Join-Path $hostStagingFolder (Split-Path $rulesetFilePath -Leaf)
        Write-Host "External ruleset downloaded to BCC shared folder ($rulesetFilePath)"
        $settings.rulesetFile = $newRulesetPath
    }
    # else: local file with no external includes - settings.rulesetFile remains unchanged

    return $settings
}

function Move-CustomCodeCopsToBaseFolder {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $settings,
        [Parameter(Mandatory = $true)]
        [string] $baseFolder
    )

    if (-not $settings.customCodeCops -or $settings.customCodeCops.Count -eq 0) {
        return $settings
    }

    $normalizedBaseFolder = [System.IO.Path]::GetFullPath($baseFolder)
    $stagedFolder = Join-Path $normalizedBaseFolder ".buildartifacts\CustomCodeCops"
    $stagedCustomCodeCops = @()
    $stagedCount = 0

    foreach ($customCodeCop in $settings.customCodeCops) {
        if ([string]::IsNullOrWhiteSpace($customCodeCop) -or $customCodeCop -like 'https://*') {
            $stagedCustomCodeCops += $customCodeCop
            continue
        }

        $sourcePath = [System.IO.Path]::GetFullPath($customCodeCop)
        if ($sourcePath.StartsWith($normalizedBaseFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
            $stagedCustomCodeCops += $sourcePath
            continue
        }

        if (-not (Test-Path -Path $sourcePath -PathType Leaf)) {
            throw "The customCodeCop file does not exist: $sourcePath"
        }

        if (-not (Test-Path -Path $stagedFolder)) {
            New-Item -Path $stagedFolder -ItemType Directory | Out-Null
        }

        $stagedCount++
        $targetPath = Join-Path $stagedFolder (Split-Path $sourcePath -Leaf)
        Copy-Item -Path $sourcePath -Destination $targetPath -Force
        Write-Host "Staged customCodeCop to $targetPath"
        $stagedCustomCodeCops += $targetPath
    }

    $settings.customCodeCops = $stagedCustomCodeCops
    return $settings
}

function Move-CustomCodeCopsToBaseFolder {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $settings,
        [Parameter(Mandatory = $true)]
        [string] $baseFolder
    )

    if (-not $settings.customCodeCops -or $settings.customCodeCops.Count -eq 0) {
        return $settings
    }

    $normalizedBaseFolder = [System.IO.Path]::GetFullPath($baseFolder)
    $stagedFolder = Join-Path $normalizedBaseFolder ".buildartifacts\CustomCodeCops"
    $stagedCustomCodeCops = @()
    $stagedCount = 0

    foreach ($customCodeCop in $settings.customCodeCops) {
        if ([string]::IsNullOrWhiteSpace($customCodeCop) -or $customCodeCop -like 'https://*') {
            $stagedCustomCodeCops += $customCodeCop
            continue
        }

        $sourcePath = [System.IO.Path]::GetFullPath($customCodeCop)
        if ($sourcePath.StartsWith($normalizedBaseFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
            $stagedCustomCodeCops += $sourcePath
            continue
        }

        if (-not (Test-Path -Path $sourcePath -PathType Leaf)) {
            throw "The customCodeCop file does not exist: $sourcePath"
        }

        if (-not (Test-Path -Path $stagedFolder)) {
            New-Item -Path $stagedFolder -ItemType Directory | Out-Null
        }

        $stagedCount++
        $targetPath = Join-Path $stagedFolder (Split-Path $sourcePath -Leaf)
        Copy-Item -Path $sourcePath -Destination $targetPath -Force
        Write-Host "Staged customCodeCop to $targetPath"
        $stagedCustomCodeCops += $targetPath
    }

    $settings.customCodeCops = $stagedCustomCodeCops
    return $settings
}
