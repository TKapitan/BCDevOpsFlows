. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Output.Helper.ps1" -Resolve)

function DetermineArtifactUrl {
    Param(
        [hashtable] $settings
    )

    $artifact = $settings.artifact
    if ($artifact.Contains('{INSIDERSASTOKEN}')) {
        $artifact = $artifact.replace('{INSIDERSASTOKEN}', '')
        OutputMessage "::Warning::Please update your artifact setting and remove {INSIDERSASTOKEN} from the setting. This is no longer needed."
    }

    OutputMessage "Checking artifact setting for repository"
    if ($artifact -eq "" -and $settings.updateDependencies) {
        $artifact = Get-BCArtifactUrl -country $settings.country -select all | Where-Object { [Version]$_.Split("/")[4] -ge [Version]$settings.applicationDependency } | Select-Object -First 1
        if (-not $artifact) {
            # Check Insider Artifacts
            $artifact = Get-BCArtifactUrl -storageAccount bcinsider -accept_insiderEula -country $settings.country -select all | Where-Object { [Version]$_.Split("/")[4] -ge [Version]$settings.applicationDependency } | Select-Object -First 1
            if (-not $artifact) {
                OutputError "No artifacts found for application dependency $($settings.applicationDependency)."
            }
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
        $segments = "$artifact/////".Split('/')
        $storageAccount = $segments[0];
        $artifactType = $segments[1]; if ($artifactType -eq "") { $artifactType = 'Sandbox' }
        $version = $segments[2]
        $country = $segments[3]; if ($country -eq "") { $country = $settings.country }
        $select = $segments[4]; if ($select -eq "") { $select = "latest" }
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
                OutputError "Invalid artifact setting ($artifact) in $repoSettingsFile. Version can only be '*' if select is first or latest."
            }
            OutputMessage "Found $($allArtifactUrls.Count) artifacts for version $version matching application dependency $($settings.applicationDependency), selecting $select."
            if (-not $artifactUrl) {
                OutputError "No artifacts found for the artifact setting ($artifact) in $repoSettingsFile, when application dependency is $($settings.applicationDependency)"
            }
        }
        else {
            $artifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $version -country $country -select $select -accept_insiderEula | Select-Object -First 1
            if (-not $artifactUrl) {
                OutputError "No artifacts found for the artifact setting ($artifact) in $repoSettingsFile"
            }
        }
        $version = $artifactUrl.Split('/')[4]
        $storageAccount = $artifactUrl.Split('/')[2]
    }

    if ($settings.additionalCountries -or $country -ne $settings.country) {
        if ($country -ne $settings.country) {
            OutputMessageWarning -Message "artifact definition in $repoSettingsFile uses a different country ($country) than the country definition ($($settings.country))"
        }
        OutputMessage "Checking Country and additionalCountries"
        # AT is the latest published language - use this to determine available country codes (combined with mapping)
        $ver = [Version]$version
        OutputMessage "https://$storageAccount/$artifactType/$version/$country"
        $atArtifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -country at -version "$($ver.Major).$($ver.Minor)" -select Latest -accept_insiderEula
        OutputMessage "Latest AT artifacts $atArtifactUrl"
        $latestATversion = $atArtifactUrl.Split('/')[4]
        $countries = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $latestATversion -accept_insiderEula -select All | ForEach-Object {
            $countryArtifactUrl = $_.Split('?')[0] # remove sas token
            $countryArtifactUrl.Split('/')[5] # get country
        }
        OutputMessage "Countries with artifacts $($countries -join ',')"
        $allowedCountries = $bcContainerHelperConfig.mapCountryCode.PSObject.Properties.Name + $countries | Select-Object -Unique
        OutputMessage "Allowed Country codes $($allowedCountries -join ',')"
        if ($allowedCountries -notcontains $settings.country) {
            OutputError "Country ($($settings.country)), specified in $repoSettingsFile is not a valid country code."
        }
        $illegalCountries = $settings.additionalCountries | Where-Object { $allowedCountries -notcontains $_ }
        if ($illegalCountries) {
            OutputError "additionalCountries contains one or more invalid country codes ($($illegalCountries -join ",")) in $repoSettingsFile."
        }
        $artifactUrl = $artifactUrl.Replace($artifactUrl.Split('/')[4], $atArtifactUrl.Split('/')[4])
    }
    return $artifactUrl
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