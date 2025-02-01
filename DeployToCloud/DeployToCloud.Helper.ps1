. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Output.Helper.ps1" -Resolve)

function CheckIfAppNeedsInstallOrUpgrade {
    Param(
        [PSCustomObject] $appJson,
        $installedApp,
        [string] $installMode
    )

    $needsInstall = $false
    $needsUpgrade = $false
    if ($installedApp) {
        $newVersion = [version]::new($appJson.Version)
        $installedVersion = [version]::new($installedApp.versionMajor, $installedApp.versionMinor, $installedApp.versionBuild, $installedApp.versionRevision)
        if ($newVersion -gt $installedVersion) {
            $msg = "Dependency app $($appJson.name) is already installed in version $installedVersion, which is lower than $newVersion."
            if ($installMode -eq 'upgrade') {
                OutputMessage "$msg Needs upgrade."
                $needsUpgrade = $true
            }
            else {
                OutputMessage "::WARNING::$msg Set DependencyInstallMode to 'upgrade' or 'forceUpgrade' to upgrade dependencies."
            }
        }
        elseif ($newVersion -lt $installedVersion) {
            OutputMessage "::WARNING::Dependency app $($appJson.name) is already installed in version $installedVersion, which is higher than $newVersion, used for this build. Please update your local copy of this dependency."
        }
        else {
            OutputMessage "Dependency app $($appJson.name) is already installed in version $installedVersion."
        }
    }
    else {
        OutputMessage "Dependency app $($appJson.name) is not installed."
        $needsInstall = $true
    }
    return $needsInstall, $needsUpgrade
}

function InstallOrUpgradeApps {
    Param(
        [hashtable] $bcAuthContext,
        [string] $environment,
        [string[]] $apps,
        [string] $installMode
    )

    $schemaSyncMode = 'Add'
    if ($installMode -eq 'ForceUpgrade') {
        $schemaSyncMode = 'Force'
        $installMode = 'upgrade'
    }
    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempPath | Out-Null
    try {
        Copy-AppFilesToFolder -appFiles $apps -folder $tempPath | Out-Null
        $apps = @(Get-ChildItem -Path $tempPath -Filter *.app | ForEach-Object { $_.FullName })
        $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.isInstalled }
        $PTEsToInstall = @()
        # Run through all apps and install or upgrade AppSource apps first (and collect PTEs)
        foreach($app in $apps) {
            # Get AppJson (works for full .app files, symbol files and also runtime packages)
            $appJson = Get-AppJsonFromAppFile -appFile $app
            $isPTE = ($appjson.idRanges.from -lt 100000 -and $appjson.idRanges.from -ge 50000)
            $installedApp = $installedApps | Where-Object { $_.id -eq $appJson.id }
            $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode
            if ($needsUpgrade) {
                if (-not $isPTE -and $installedApp.publishedAs.Trim() -eq 'Dev') {
                    OutputMessage "::WARNING::Dependency AppSource App $($appJson.name) is published in Dev scoope. Cannot upgrade."
                    $needsUpgrade = $false
                }
            }
            if ($needsUpgrade -or $needsInstall) {
                if ($isPTE) {
                    $PTEsToInstall += $app
                }
                else {
                    Install-BcAppFromAppSource -bcAuthContext $bcAuthContext -environment $environment -appId $appJson.id -acceptIsvEula -installOrUpdateNeededDependencies
                    # Update installed apps list as dependencies may have changed / been installed
                    $installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $environment | Where-Object { $_.isInstalled }
                }
            }
        }
        if ($PTEsToInstall) {
            # Install or upgrade PTEs
            Publish-PerTenantExtensionApps -bcAuthContext $bcAuthContext -environment $environment -appFiles $PTEsToInstall -SchemaSyncMode $schemaSyncMode
        }
    }
    finally {
        Remove-Item -Path $tempPath -Force -Recurse
    }
}
