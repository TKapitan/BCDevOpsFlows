. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

function AddArtifactUrlToCache {
    param(
        [Parameter(Mandatory = $true)]
        [string] $artifact,
        [Parameter(Mandatory = $true)]
        [string] $artifactUrl
    )

    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json
    if ($settings.artifactUrlCacheKeepHours -eq 0) {
        OutputDebug -Message "Skipping caching of artifact URL because artifactUrlcacheKeepHours is set to 0"
        return
    }
    if (!$settings.writableFolderPath) {
        Write-Warning "Artifact URL caching is enabled, but writableFolderPath is not set. Skipping caching of artifact URL."
        return
    }

    $artifactUrlCacheFile = Join-Path -Path $settings.writableFolderPath -ChildPath "ArtifactUrlCache.json"
    $artifactUrlCacheContent = @()
    if (Test-Path $artifactUrlCacheFile) {
        $artifactUrlCacheContent = Get-Content $artifactUrlCacheFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -eq $artifactUrlCacheContent) { $artifactUrlCacheContent = @() }
    }

    $currentDateTime = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $existingItem = $artifactUrlCacheContent | Where-Object { $_.artifact -eq $artifact }

    if ($existingItem) {
        Write-Host "Updating cached artifact URL '$artifactUrl' for artifact $artifact, setting updatedAt to $currentDateTime"
        $existingItem.artifactUrl = $artifactUrl
        $existingItem.updatedAt = $currentDateTime
    }
    else {
        Write-Host "Caching artifact URL '$artifactUrl' for artifact $artifact, setting updatedAt to $currentDateTime"
        $newItem = [ordered]@{
            artifact    = $artifact
            artifactUrl = $artifactUrl
            updatedAt   = $currentDateTime
        }
        $artifactUrlCacheContent = @($artifactUrlCacheContent) + $newItem
    }
    
    $jsonOutput = $artifactUrlCacheContent | ConvertTo-Json -Depth 99
    [System.IO.File]::WriteAllText($artifactUrlCacheFile, $jsonOutput)
}

function GetArtifactUrlFromCache {
    param(
        [Parameter(Mandatory = $true)]
        [string] $artifact
    )

    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json
    if ($settings.artifactUrlCacheKeepHours -eq 0) {
        OutputDebug -Message "Artifact URL caching is disabled because artifactUrlcacheKeepHours is set to 0"
        return
    }
    if (!$settings.writableFolderPath) {
        Write-Warning "Artifact URL caching is enabled, but writableFolderPath is not set."
        return
    }

    $artifactUrlCacheFile = Join-Path -Path $settings.writableFolderPath -ChildPath "ArtifactUrlCache.json"
    if (!(Test-Path $artifactUrlCacheFile)) {
        OutputDebug -Message "Artifact URL cache file not found"
        return
    }

    $artifactUrlCacheContent = Get-Content $artifactUrlCacheFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (!$artifactUrlCacheContent) { 
        OutputDebug -Message "Artifact URL cache file is empty"
        return
    }

    $cachedItem = $artifactUrlCacheContent | Where-Object { $_.artifact -eq $artifact }
    if (!$cachedItem) {
        Write-Host "No cached artifact URL found for artifact $artifact"
        return
    }

    try {
        $updatedAt = [DateTime]::ParseExact($cachedItem.updatedAt, "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        $expiryTime = $updatedAt.AddHours($settings.artifactUrlCacheKeepHours)
        
        if ([DateTime]::UtcNow -gt $expiryTime) {
            Write-Host "Cached artifact URL for artifact $artifact has expired at $expiryTime (current time: $([DateTime]::UtcNow))"
            return
        }
        Write-Host "Using cached artifact URL '$($cachedItem.artifactUrl)' for artifact $artifact"
        return $cachedItem.artifactUrl
    }
    catch {
        Write-Warning "Error processing cache entry for artifact $($artifact): $_"
        return
    }
}