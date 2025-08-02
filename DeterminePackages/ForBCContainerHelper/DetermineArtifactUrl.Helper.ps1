function DetermineArtifactUrl {
    Param(
        [hashtable] $settings
    )

    . (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\CacheArtifactUrl.Helper.ps1" -Resolve)

    $artifact = $settings.artifact
    if ($artifact.Contains('{INSIDERSASTOKEN}')) {
        throw "{INSIDERSASTOKEN} is no longer supported in the artifact setting."
    }

    Write-Host "Checking artifact setting for repository"
    if ($artifact -eq "" -and $settings.updateDependencies) {
        $artifact = Get-BCArtifactUrl -country $settings.country -select all | Where-Object { [Version]$_.Split("/")[4] -ge [Version]$settings.applicationDependency } | Select-Object -First 1
        if (-not $artifact) {
            # Check Insider Artifacts
            $artifact = Get-BCArtifactUrl -storageAccount bcinsider -accept_insiderEula -country $settings.country -select all | Where-Object { [Version]$_.Split("/")[4] -ge [Version]$settings.applicationDependency } | Select-Object -First 1
            if (-not $artifact) {
                throw "No artifacts found for application dependency $($settings.applicationDependency)."
            }
        }
    }

    $isAppJsonArtifact = $artifact.ToLower() -eq "////appjson"
    $ENV:AL_APPJSONARTIFACT = $isAppJsonArtifact
    Write-Host "##vso[task.setvariable variable=AL_APPJSONARTIFACT;]$isAppJsonArtifact"
    OutputDebug -Message "Set environment variable AL_APPJSONARTIFACT to ($ENV:AL_APPJSONARTIFACT)"

    $artifact = AddArtifactDefaultValues -artifact $artifact
    try {
        $artifactCacheMutexName = "ArtifactUrlCache-$artifact"
        $artifactCacheMutex = New-Object System.Threading.Mutex($false, $artifactCacheMutexName)
        if ($artifact -ne "" -and $artifact -notlike "https://*") {
            # Check if the artifact is in the cache
            try {
                if (!$artifactCacheMutex.WaitOne(1000)) {
                    Write-Host "Waiting for other process updating $artifact Artifact URL cache"
                    $artifactCacheMutex.WaitOne() | Out-Null
                    Write-Host "Other process completed updating $artifact Artifact URL cache"
                }
            }
            catch [System.Threading.AbandonedMutexException] {
                Write-Host "Other process terminated abnormally"
            }
            $artifactUrlFromCacheUrl = GetArtifactUrlFromCache -settings $settings -artifact $artifact
            if ($artifactUrlFromCacheUrl) {
                # If found, the value is https url
                $artifact = $artifactUrlFromCacheUrl;
            }
        }

        if ($artifact -like "https://*") {
            $artifactUrl = $artifact
            $storageAccount = ("$artifactUrl////".Split('/')[2])
            $artifactType = ("$artifactUrl////".Split('/')[3])
            $version = ("$artifactUrl////".Split('/')[4])
            $country = ("$artifactUrl////".Split('?')[0].Split('/')[5])
        }
        else {
            $segments = $artifact.Split('/')
            $storageAccount = $segments[0];
            $artifactType = $segments[1];
            $version = $segments[2]
            $country = $segments[3];
            $select = $segments[4];
            if ($version -eq '*') {
                $version = "$(([Version]$settings.applicationDependency).Major).$(([Version]$settings.applicationDependency).Minor)"
                $allArtifactUrls = @(Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $version -country $country -select all -accept_insiderEula | Where-Object { [Version]$_.Split('/')[4] -ge [Version]$settings.applicationDependency })
                if ($select -eq 'latest') {
                    $artifactUrl = $allArtifactUrls | Select-Object -Last 1
                }
                elseif ($select -eq 'first') {
                    $artifactUrl = $allArtifactUrls | Select-Object -First 1
                }
                else {
                    throw "Invalid artifact setting ($artifact) in $repoSettingsFile. Version can only be '*' if select is first or latest."
                }
                Write-Host "Found $($allArtifactUrls.Count) artifacts for version $version matching application dependency $($settings.applicationDependency), selecting $select."
                if (-not $artifactUrl) {
                    throw "No artifacts found for the artifact setting ($artifact) in $repoSettingsFile, when application dependency is $($settings.applicationDependency)"
                }
            }
            else {
                $artifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $version -country $country -select $select -accept_insiderEula | Select-Object -First 1
                if (-not $artifactUrl) {
                    throw "No artifacts found for the artifact setting ($artifact) in $repoSettingsFile"
                }
            }

            try {
                if (!$artifactCacheMutex.WaitOne(1000)) {
                    Write-Host "Waiting for other process updating $artifact Artifact URL cache"
                    $artifactCacheMutex.WaitOne() | Out-Null
                    Write-Host "Other process completed updating $artifact Artifact URL cache"
                }
            }
            catch [System.Threading.AbandonedMutexException] {
                Write-Host "Other process terminated abnormally"
            }
            AddArtifactUrlToCache -settings $settings -artifact $artifact -ArtifactUrl $artifactUrl
            $version = $artifactUrl.Split('/')[4]
            $storageAccount = $artifactUrl.Split('/')[2]
        }
    }
    finally {
        $artifactCacheMutex.ReleaseMutex()
        $artifactCacheMutex.Close()
    }

    if ($settings.additionalCountries -or $country -ne $settings.country) {
        if ($country -ne $settings.country) {
            OutputWarning -Message "artifact definition in $repoSettingsFile uses a different country ($country) than the country definition ($($settings.country))"
        }
        Write-Host "Checking Country and additionalCountries"
        # AT is the latest published language - use this to determine available country codes (combined with mapping)
        $ver = [Version]$version
        Write-Host "https://$storageAccount/$artifactType/$version/$country"
        $atArtifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -country at -version "$($ver.Major).$($ver.Minor)" -select Latest -accept_insiderEula
        Write-Host "Latest AT artifacts $atArtifactUrl"
        $latestATversion = $atArtifactUrl.Split('/')[4]
        $countries = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $latestATversion -accept_insiderEula -select All | ForEach-Object {
            $countryArtifactUrl = $_.Split('?')[0] # remove sas token
            $countryArtifactUrl.Split('/')[5] # get country
        }
        Write-Host "Countries with artifacts $($countries -join ',')"
        $allowedCountries = $bcContainerHelperConfig.mapCountryCode.PSObject.Properties.Name + $countries | Select-Object -Unique
        Write-Host "Allowed Country codes $($allowedCountries -join ',')"
        if ($allowedCountries -notcontains $settings.country) {
            throw "Country ($($settings.country)), specified in $repoSettingsFile is not a valid country code."
        }
        $illegalCountries = $settings.additionalCountries | Where-Object { $allowedCountries -notcontains $_ }
        if ($illegalCountries) {
            throw "additionalCountries contains one or more invalid country codes ($($illegalCountries -join ",")) in $repoSettingsFile."
        }
        $artifactUrl = $artifactUrl.Replace($artifactUrl.Split('/')[4], $atArtifactUrl.Split('/')[4])
    }
    return $artifactUrl
}

function AddArtifactDefaultValues {
    Param(
        [string] $artifact
    )

    if ($artifact -like "https://*") {
        return $artifact
    }
    $segments = "$artifact/////".Split('/')

    $storageAccount = $segments[0];
    $artifactType = $segments[1]; if ($artifactType -eq "") { $artifactType = 'Sandbox' }
    $version = $segments[2]
    $country = $segments[3]; if ($country -eq "") { $country = $settings.country }
    $select = $segments[4]; if ($select -eq "") { $select = "latest" }

    if ($select -eq "appjson") {
        Write-Host "Using app.json artifact"
        $baseAppFolder = "$ENV:PIPELINE_WORKSPACE\App\App"
        $appJsonContent = Get-Content "$baseAppFolder\app.json" -Encoding UTF8 | ConvertFrom-Json

        $appJsonVersionSegments = $appJsonContent.application.Split('.')
        $version = "$($appJsonVersionSegments[0]).$($appJsonVersionSegments[1])"
        $select = "latest"
    }
    $calculatedArtifact = "$storageAccount/$artifactType/$version/$country/$select"
    Write-Host "Calculated artifact: $calculatedArtifact"
    return $calculatedArtifact
}

# Copy a HashTable to ensure non case sensitivity (Issue #385)
function Copy-HashTable() {
    [CmdletBinding()]
    [OutputType([System.Collections.HashTable])]
    Param(
        [parameter(ValueFromPipeline)]
        [hashtable] $object
    )
    Process {
        $ht = @{}
        if ($object) {
            $object.Keys | ForEach-Object {
                $ht[$_] = $object[$_]
            }
        }
        $ht
    }
}