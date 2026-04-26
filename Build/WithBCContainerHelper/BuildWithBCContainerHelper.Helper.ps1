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
