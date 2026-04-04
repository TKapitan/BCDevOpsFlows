. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Common\Import-Common.ps1" -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\NuGet.Helper.ps1" -Resolve)

function Get-NuGetPackagesAndAddToSettings {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $settings,
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $appJsonContent,
        [Parameter(Mandatory = $true)]
        [string] $sourceProperty,
        [Parameter(Mandatory = $true)]
        [string] $targetProperty,
        [Parameter(Mandatory = $false)]
        [hashtable] $packageParams
    )
    
    if ($settings[$sourceProperty]) {
        $trustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL
        $settings[$sourceProperty] | ForEach-Object {
            $packageName = $_
            $packageParts = $packageName -split '\.'
            $packageId = $packageParts[2]
            if ($packageId -eq $appJsonContent.id) {
                Write-Host " - skipping package $packageName (matches current app ID)"
            }
            else {
                $dependency = @{
                    "id"        = $packageId
                    "name"      = $packageParts[1]
                    "publisher" = $packageParts[0]
                }
                $currentPackageParams = @{}
                if ($packageParams) {
                    $currentPackageParams = $packageParams.Clone()
                }
                . (Join-Path -Path $PSScriptRoot -ChildPath "..\CustomLogic\GetDependencyVersionFilter.ps1" -Resolve)
                $dependencyVersionFilter = GetDependencyVersionFilter -appJson $appJsonContent -dependency $dependency
                if ($dependencyVersionFilter -ne '') {
                    OutputDebug -Message "Using custom dependency version filter '$dependencyVersionFilter' for dependency $($dependency.name)."
                    $currentPackageParams["version"] = $dependencyVersionFilter
                }

                $appFile = Get-BCDevOpsFlowsNuGetPackage -trustedNugetFeeds $trustedNuGetFeeds -packageName $packageName @currentPackageParams
                if (-not $appFile) {
                    throw "Package $packageName not found in NuGet feeds"
                }
                if (!$settings[$targetProperty]) {
                    $settings[$targetProperty] = @()
                }
                $settings[$targetProperty] += $appFile
                Write-Host " - adding app: $packageName"
            }
        }
    }
}

function Get-DependenciesFromNuGet {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $settings,
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $appJsonContent
    )

    $settings = $settings | Copy-HashTable
    Write-Host "Analyzing Test App Dependencies"
    if ($settings.testFolders) { $settings.installTestRunner = $true }
    if ($settings.bcptTestFolders) { $settings.installPerformanceToolkit = $true }

    if (!$settings.doNotRunBcptTests -and !$settings.bcptTestFolders) {
        Write-Host "No performance test apps found in bcptTestFolders in settings."
        $settings.doNotRunBcptTests = $true
    }
    if (!$settings.doNotBuildTests -and !$settings.testFolders) {
        OutputWarning -Message "No test apps found in testFolders in settings, skipping tests."
        $settings.doNotBuildTests = $true
    }
    if (!$settings.doNotBuildTests) {
        $folderFound = $false
        foreach ($folderName in $settings.testFolders) {
            $testFolder = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath $folderName
            if (Test-Path $testFolder) {
                $folderFound = $true
            }
        }
        if (-not $folderFound) {
            OutputWarning -Message "Test folder specified in settings but the folder does not exist, skipping tests."
            $settings.doNotBuildTests = $true
        }
    }
    if (!$settings.appFolders) {
        OutputWarning -Message "No apps found in appFolders in settings."
    }
    Write-Host "Analyzing dependencies completed"
    
    Write-Host "Checking appDependenciesNuGet and testDependenciesNuGet"
    $getDependencyNuGetPackageParams = @{}
    if ($ENV:AL_ALLOWPRERELEASE -eq "true") {
        $getDependencyNuGetPackageParams += @{
            "allowPrerelease" = $true
        }
    }

    # Process app dependencies from NuGet
    Write-Host "Adding app dependencies:"
    Get-NuGetPackagesAndAddToSettings -settings $settings -appJsonContent $appJsonContent -sourceProperty "appDependenciesNuGet" -targetProperty "appDependencies" -packageParams $getDependencyNuGetPackageParams

    if (-not $settings.doNotBuildTests) {
        # Process test dependencies from NuGet
        Write-Host "Adding test dependencies:"
        Get-NuGetPackagesAndAddToSettings -settings $settings -appJsonContent $appJsonContent -sourceProperty "testDependenciesNuGet" -targetProperty "testDependencies" -packageParams $getDependencyNuGetPackageParams
    }

    Write-Host "Checking installAppsNuGet and installTestAppsNuGet"
    
    # Process install apps from NuGet
    Write-Host "Adding additional apps to install:"
    Get-NuGetPackagesAndAddToSettings -settings $settings -appJsonContent $appJsonContent -sourceProperty "installAppsNuGet" -targetProperty "installApps" -packageParams $getDependencyNuGetPackageParams

    if (-not $settings.doNotBuildTests) {
        # Process install test apps from NuGet
        Write-Host "Adding additional test apps to install:"
        Get-NuGetPackagesAndAddToSettings -settings $settings -appJsonContent $appJsonContent -sourceProperty "installTestAppsNuGet" -targetProperty "installTestApps" -packageParams $getDependencyNuGetPackageParams
    }

    return $settings
}

function Get-PreviousReleaseFromNuGet {
    [CmdletBinding()]
    Param(
        [hashtable] $settings
    )

    $settings = $settings | Copy-HashTable
    if ($settings.skipUpgrade -or $null -eq $settings.appFolders -or $settings.appFolders.Count -eq 0) {
        $settings.previousRelease = @()
        return $settings
    }

    Write-Host "Locating previous release" 
    $appJsonContent = Get-AppJson -settings $settings
    $trustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL -trustMicrosoftNuGetFeeds $settings.trustMicrosoftNuGetFeeds
    $packageId = Get-BCDevOpsFlowsNuGetPackageId -id $appJsonContent.id -name $appJsonContent.name -publisher $appJsonContent.publisher
    $appFile = Get-BCDevOpsFlowsNuGetPackage -trustedNugetFeeds $trustedNuGetFeeds -packageName $packageId
    if ($appFile) {
        if (!$settings.previousRelease) {
            $settings.previousRelease = @()
        }
        $settings.previousRelease += $appFile
        Write-Host "Adding previous release from NuGet: $packageId"
    }
    else {
        OutputWarning -Message "No previous release found in NuGet for $packageId"
    }
    return $settings
}

function Get-LatestNuGetPackageVersion {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string] $packageName,
        [switch] $allowPrerelease
    )

    $url = "https://api.nuget.org/v3-flatcontainer/$($packageName.ToLowerInvariant())/index.json"
    $response = Invoke-RestMethod -Uri $url
    $versions = $response.versions
    if (-not $allowPrerelease) {
        $versions = $versions | Where-Object { $_ -notmatch '-' }
    }
    if (-not $versions -or $versions.Count -eq 0) {
        throw "No versions found for NuGet package $packageName"
    }
    return $versions[-1]
}

function Update-ALCopsAnalyzers {
    [CmdletBinding()]
    Param(
        [hashtable] $settings
    )

    $alcopsAnalyzers = @(
        @{ Setting = "enableALCopsLinterCop"; FileName = "ALCops.LinterCop.dll" },
        @{ Setting = "enableALCopsApplicationCop"; FileName = "ALCops.ApplicationCop.dll" },
        @{ Setting = "enableALCopsDocumentationCop"; FileName = "ALCops.DocumentationCop.dll" },
        @{ Setting = "enableALCopsFormattingCop"; FileName = "ALCops.FormattingCop.dll" },
        @{ Setting = "enableALCopsPlatformCop"; FileName = "ALCops.PlatformCop.dll" },
        @{ Setting = "enableALCopsTestAutomationCop"; FileName = "ALCops.TestAutomationCop.dll" }
    )

    $enabledAnalyzers = $alcopsAnalyzers | Where-Object { $settings[$_.Setting] }
    if (-not $enabledAnalyzers) {
        return $settings
    }

    Write-Host "Determining ALCops analyzers"
    $packageName = "ALCops.Analyzers"
    $alcopsVersion = $settings.alcopsVersion
    if (-not $alcopsVersion -or $alcopsVersion -eq "latest") {
        Write-Host "Resolving latest stable ALCops.Analyzers version"
        $alcopsVersion = Get-LatestNuGetPackageVersion -packageName $packageName
    }
    elseif ($alcopsVersion -eq "preview") {
        Write-Host "Resolving latest preview ALCops.Analyzers version"
        $alcopsVersion = Get-LatestNuGetPackageVersion -packageName $packageName -allowPrerelease
    }
    Write-Host "Using ALCops.Analyzers version: $alcopsVersion"

    $packagePath = DownloadNugetPackage -packageName $packageName -packageVersion $alcopsVersion

    # Determine target framework based on BC major version
    # AL Language extension v16.0+ uses net8.0, below uses netstandard2.1
    # BC 28+ ships with AL Language extension v16+
    $bcMajorVersion = [int]$ENV:AL_BCMAJORVERSION
    $targetFramework = "net8.0"
    if ($bcMajorVersion -lt 28) {
        $targetFramework = "netstandard2.1"
    }
    Write-Host "Using ALCops target framework: $targetFramework (BC version: $bcMajorVersion)"

    $libPath = Join-Path $packagePath "lib/$targetFramework"
    if (-not (Test-Path $libPath)) {
        $availableFrameworks = Get-ChildItem (Join-Path $packagePath 'lib') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        throw "ALCops target framework path not found: $libPath. Available frameworks: $($availableFrameworks -join ', ')"
    }

    # Always add ALCops.Common.dll (required by all ALCops analyzers)
    $commonDll = Join-Path $libPath "ALCops.Common.dll"
    if (Test-Path $commonDll) {
        $settings.customCodeCops += $commonDll
        Write-Host "Added ALCops.Common.dll"
    }
    else {
        Write-Warning "ALCops.Common.dll not found at $commonDll"
    }

    # Add enabled analyzer DLLs
    foreach ($analyzer in $enabledAnalyzers) {
        $dllPath = Join-Path $libPath $analyzer.FileName
        if (Test-Path $dllPath) {
            $settings.customCodeCops += $dllPath
            Write-Host "Added $($analyzer.FileName)"
        }
        else {
            Write-Warning "$($analyzer.FileName) not found at $dllPath"
        }
    }

    return $settings
}

function Update-CustomCodeCops {
    [CmdletBinding()]
    Param(
        [hashtable] $settings,
        [string] $runWith
    )

    if (!$settings.customCodeCops) {
        $settings.customCodeCops = @()
    }
    # Strip previously added LinterCop and ALCops entries to avoid duplicates on re-runs
    $settings.customCodeCops = $settings.customCodeCops | Where-Object { $_ -notlike "https://github.com/StefanMaron/BusinessCentral.LinterCop*" -and $_ -notmatch 'ALCops\.(Common|LinterCop|ApplicationCop|DocumentationCop|FormattingCop|PlatformCop|TestAutomationCop)\.dll$' }
    if ($settings.customCodeCops.Count -eq 0) {
        $settings.customCodeCops = @()
    }    
    
    if ($settings.enableLinterCop) {
        Write-Warning "enableLinterCop is deprecated and will be removed in a future release. Please migrate to ALCops analyzers (e.g. enableALCopsLinterCop). See https://alcops.dev/docs/lintercop-migration/ for migration guide."
        $bcMajorVersion = [int]$ENV:AL_BCMAJORVERSION
        if ($runWith.ToLowerInvariant() -eq 'nuget') {
            if ($bcMajorVersion -le 27) {
                $bcMajorVersion = 27
            }
        } else {
            if ($settings.vsixFile.ToLowerInvariant() -eq 'latest') {
                $bcMajorVersion = 100
            } elseif ($settings.vsixFile.ToLowerInvariant() -eq 'preview') {
                $bcMajorVersion = 1000
            }
        }
        Write-Host "Determining LinterCop version"     
        $linterCopURL = "" # https://github.com/StefanMaron/BusinessCentral.LinterCop/releases/latest/download/BusinessCentral.LinterCop.dll
        switch ($bcMajorVersion) {
            1000 { $linterCopURL = "BusinessCentral.LinterCop.AL-PreRelease.dll" }
            100 { $linterCopURL = "BusinessCentral.LinterCop.dll" }
            28 { $linterCopURL = "BusinessCentral.LinterCop.AL-PreRelease.dll" }
            27 { $linterCopURL = "BusinessCentral.LinterCop.dll" }
            26 { $linterCopURL = "BusinessCentral.LinterCop.AL-15.2.1630495.dll" }
            25 { $linterCopURL = "BusinessCentral.LinterCop.AL-14.3.1327807.dll" }
            24 { $linterCopURL = "BusinessCentral.LinterCop.AL-13.1.1065068.dll" }
            23 { $linterCopURL = "BusinessCentral.LinterCop.AL-12.7.964847.dll" }
            default { 
                Write-Warning "LinterCop is not available for BC version $($ENV:AL_BCMAJORVERSION) (adjusted to $bcMajorVersion). Skipping LinterCop configuration."
            }
        }
        if ($linterCopURL -ne "") {
            Write-Host "Using LinterCop for version $ENV:AL_BCMAJORVERSION (adjusted to $bcMajorVersion), URL: $linterCopURL"
            $settings.customCodeCops += "https://github.com/StefanMaron/BusinessCentral.LinterCop/releases/latest/download/$linterCopURL"
        }
    }

    # Process ALCops analyzers
    $settings = Update-ALCopsAnalyzers -settings $settings

    Write-Host "Configured custom CodeCops:"
    $settings.customCodeCops | ForEach-Object {
        Write-Host "- $_"
    }
    return $settings
}