. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

function AddArtifactUrlToCache {
    param(
        [Parameter(Mandatory = $true)]
        [string] $artifact,
        [Parameter(Mandatory = $true)]
        [string] $ArtifactUrl
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

    $artifactUrlCacheFile = "$($settings.writableFolderPath)\ArtifactUrlCache.json"
    $artifactUrlCacheContent = @()
    if (Test-Path $artifactUrlCacheFile) {
        $artifactUrlCacheContent = Get-Content $artifactUrlCacheFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if (!$artifactUrlCacheContent) { $artifactUrlCacheContent = @() }
    }

    $currentDateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $existingItem = $artifactUrlCacheContent | Where-Object { $_.artifact -eq $artifact }

    if ($existingItem) {
        $existingItem.artifactUrl = $ArtifactUrl
        $existingItem.updatedAt = $currentDateTime
        Write-Host "Updating cached artifact URL '$ArtifactUrl' for artifact $artifact"
    }
    else {
        $newItem = @{
            artifact    = $artifact
            artifactUrl = $ArtifactUrl
            updatedAt   = $currentDateTime
        }
        $artifactUrlCacheContent += $newItem
        Write-Host "Caching artifact URL '$ArtifactUrl' for artifact $artifact"
    }
    $artifactUrlCacheContent | ConvertTo-Json | Set-Content $artifactUrlCacheFile
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

    $artifactUrlCacheFile = "$($settings.writableFolderPath)\ArtifactUrlCache.json"
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

    $updatedAt = [DateTime]::ParseExact($cachedItem.updatedAt, "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    $expiryTime = $updatedAt.AddHours($settings.artifactUrlCacheKeepHours)
    
    if ((Get-Date).ToUniversalTime() -gt $expiryTime) {
        Write-Host "Cached artifact URL for artifact $artifact has expired"
        return
    }
    Write-Host "Using cached artifact URL '$($cachedItem.artifactUrl)' for artifact $artifact"
    return $cachedItem.artifactUrl
}
