
. (Join-Path -Path $PSScriptRoot -ChildPath "..\DeterminePackages\ForBCContainerHelper\DetermineArtifactUrl.Helper.ps1" -Resolve)

function AnalyzeRepo {
    [CmdletBinding()]
    Param(
        [hashtable] $settings
    )
    $settings = $settings | Copy-HashTable

    Write-Host "::group::Analyzing repository"
    # Check applicationDependency
    [Version]$settings.applicationDependency | Out-null

    Write-Host "Checking type"
    if ($settings.type -eq "PTE") {
        if (!$settings.Contains('enablePerTenantExtensionCop')) {
            $settings.Add('enablePerTenantExtensionCop', $true)
        }
        if (!$settings.Contains('enableAppSourceCop')) {
            $settings.Add('enableAppSourceCop', $false)
        }
    }
    elseif ($settings.type -eq "AppSource App") {
        if (!$settings.Contains('enablePerTenantExtensionCop')) {
            $settings.Add('enablePerTenantExtensionCop', $false)
        }
        if (!$settings.Contains('enableAppSourceCop')) {
            $settings.Add('enableAppSourceCop', $true)
        }
        if (!$settings.Contains('removeInternalsVisibleTo')) {
            $settings.Add('removeInternalsVisibleTo', $true)
        }
    }
    else {
        throw "The type, specified in $repoSettingsFile, must be either 'PTE' or 'AppSource App'. It is '$($settings.type)'."
    }
    if ($settings.enableAppSourceCop -and !$settings.appSourceCopMandatoryAffixes -and !$settings.skipAppSourceCopMandatoryAffixesEnforcement) {
        throw "For AppSource Apps with AppSourceCop enabled, you need to specify AppSourceCopMandatoryAffixes in $repoSettingsFile"
    }

    # Avoid checking the artifact setting in AnalyzeRepo if we have an artifactUrl
    if ($settings.artifact -notlike "https://*" -and $settings.runWith -ne "NuGet") {
        $artifactUrl = DetermineArtifactUrl -settings $settings
        $settings.artifact = $artifactUrl
        if ([Version]$settings.applicationDependency -gt [Version]$artifactUrl.Split('/')[4]) {
            throw "Application dependency is set to $($settings.applicationDependency), which isn't compatible with the artifact version $version"
        }
    }
    Write-Host "::endgroup::"

    Write-Host "Analyzing repository completed"
    return $settings
}
