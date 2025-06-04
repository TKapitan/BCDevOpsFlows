# Copy of NuGet class from BCContainerHelper, required changed to support Azure DevOps preview packages

. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\WriteOutput.Helper.ps1" -Resolve)

<# 
 .Synopsis
  PROOF OF CONCEPT PREVIEW: Get Business Central NuGet Package from NuGet Server
 .Description
  Find Business Central NuGet Package from NuGet Server
 .OUTPUTS
  BcDevOpsFlowsNuGetFeed class, packageId and package Version
 .PARAMETER trustedNugetFeeds
  Array of objects with nuget feeds to trust in the format @([PSCustomObject]@{Url="https://api.nuget.org/v3/index.json"; Token=""; Patterns=@('*'); Fingerprints=@()})
 .PARAMETER packageName
  Package Name to search for.
  This can be the full name or a partial name with wildcards.
  If more than one package is found, matching the name, an error is thrown.
 .PARAMETER version
  Package Version, following the nuget versioning rules
  https://learn.microsoft.com/en-us/nuget/concepts/package-versioning#version-ranges
 .PARAMETER silent
  Suppress output
 .PARAMETER select
  Select the package to download if more than one package is found matching the name and version
  - Earliest: Select the earliest version
  - Latest: Select the latest version (default)
  - LatestMajor: Select the latest version of the major version
  - LatestMinor: Select the latest version of the minor version
  - Exact: Select the exact version
  - Any: Select the first version found
 .PARAMETER allowPrerelease
  Include prerelease versions in the search
 .EXAMPLE
  $feed, $packageId, $packageVersion = Find-BCDevOpsFlowsNuGetPackage -packageName 'FreddyKristiansen.BingMapsPTE.165d73c1-39a4-4fb6-85a5-925edc1684fb'
 .EXAMPLE
  $feed, $packageId, $packageVersion = Find-BCDevOpsFlowsNuGetPackage -trustedNugetFeeds $trustedNugetFeeds -nuGetToken $nuGetToken -packageName '437dbf0e-84ff-417a-965d-ed2bb9650972' -allowPrerelease
#>
Function Find-BCDevOpsFlowsNuGetPackage {
    Param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $trustedNugetFeeds,
        [Parameter(Mandatory = $true)]
        [string] $packageName,
        [Parameter(Mandatory = $false)]
        [string] $version = '0.0.0.0',
        [Parameter(Mandatory = $false)]
        [string[]] $excludeVersions = @(),
        [Parameter(Mandatory = $false)]
        [ValidateSet('Earliest', 'Latest', 'LatestMajor', 'LatestMinor', 'Exact', 'Any')]
        [string] $select = 'Latest',
        [switch] $allowPrerelease
    )

    function IsSameMajorVersion {
        param(
            [string]$version1,
            [string]$version2
        )
        $v1Parts = $version1 -split '\.'
        $v2Parts = $version2 -split '\.'
        OutputDebug -Message "Comparing Major versions: $version1 vs $version2"
        return $v1Parts[0] -eq $v2Parts[0]
    }

    function IsSameMajorMinorVersion {
        param(
            [string]$version1,
            [string]$version2
        )
        $v1Parts = $version1 -split '\.'
        $v2Parts = $version2 -split '\.'
        OutputDebug -Message "Comparing Major.Minor versions: $version1 vs $version2"
        return $v1Parts[0] -eq $v2Parts[0] -and $v1Parts[1] -eq $v2Parts[1]
    }

    $bestmatch = $null
    # Search all trusted feeds for the package
    foreach ($feed in ($trustedNugetFeeds)) {
        if ($feed -and $feed.Url) {
            Write-Host "Search NuGetFeed $($feed.Url)"
            if (!($feed.PSObject.Properties.Name -eq 'Token')) { $feed | Add-Member -MemberType NoteProperty -Name 'Token' -Value '' }
            if (!($feed.PSObject.Properties.Name -eq 'Patterns')) { $feed | Add-Member -MemberType NoteProperty -Name 'Patterns' -Value @('*') }
            if (!($feed.PSObject.Properties.Name -eq 'Fingerprints')) { $feed | Add-Member -MemberType NoteProperty -Name 'Fingerprints' -Value @() }
            $nuGetFeed = [BcDevOpsFlowsNuGetFeed]::Create($feed.Url, $feed.Token, $feed.Patterns, $feed.Fingerprints)
            $packages = $nuGetFeed.Search($packageName, $allowPrerelease)
            if ($packages) {
                foreach ($package in $packages) {
                    $packageId = $package.Id
                    Write-Host "PackageId: $packageId"
                    $packageVersion = $nuGetFeed.FindPackageVersion($package, $version, $excludeVersions, $select, $allowPrerelease.IsPresent)
                    if (!$packageVersion) {
                        Write-Host "No package found matching version '$version' for package id $($packageId)"
                        continue
                    }
                    elseif ($bestmatch) {
                        if ($select -eq 'LatestMajor') {
                            if (!IsSameMajorVersion -version1 $packageVersion -version2 $version) {
                                continue
                            }
                        }
                        if ($select -eq 'LatestMinor') {
                            if (!IsSameMajorMinorVersion -version1 $packageVersion -version2 $version) {
                                continue
                            }
                        }
                        # We already have a match, check if this is a better match
                        if (($select -eq 'Earliest' -and ([BcDevOpsFlowsNuGetFeed]::CompareVersions($packageVersion, $bestmatch.PackageVersion) -eq -1)) -or 
                            ($select -in @('Latest', 'LatestMinor', 'LatestMajor') -and ([BcDevOpsFlowsNuGetFeed]::CompareVersions($packageVersion, $bestmatch.PackageVersion) -eq 1))) {
                            $bestmatch = [PSCustomObject]@{
                                "Feed"           = $nuGetFeed
                                "PackageId"      = $packageId
                                "PackageVersion" = $packageVersion
                            }
                        }
                    }
                    elseif ($select -eq 'Exact') {
                        # We only have a match if the version is exact
                        if ([BcDevOpsFlowsNuGetFeed]::NormalizeVersionStr($packageVersion) -eq [BcDevOpsFlowsNuGetFeed]::NormalizeVersionStr($version)) {
                            $bestmatch = [PSCustomObject]@{
                                "Feed"           = $nuGetFeed
                                "PackageId"      = $packageId
                                "PackageVersion" = $packageVersion
                            }
                            break
                        }
                    }
                    else {
                        if ($select -eq 'LatestMajor') {
                            if (!IsSameMajorVersion -version1 $packageVersion -version2 $version) {
                                continue
                            }
                        }
                        if ($select -eq 'LatestMinor') {
                            if (!IsSameMajorMinorVersion -version1 $packageVersion -version2 $version) {
                                continue
                            }
                        }
                        $bestmatch = [PSCustomObject]@{
                            "Feed"           = $nuGetFeed
                            "PackageId"      = $packageId
                            "PackageVersion" = $packageVersion
                        }
                        # If we are looking for any match, we can stop here
                        if ($select -eq 'Any') {
                            break
                        }
                    }
                }
            }
        }
        if ($bestmatch -and ($select -eq 'Any' -or $select -eq 'Exact')) {
            # If we have an exact match or any match, we can stop here
            break
        }
    }
    if ($bestmatch) {
        return $bestmatch.Feed, $bestmatch.PackageId, $bestmatch.PackageVersion
    }
}