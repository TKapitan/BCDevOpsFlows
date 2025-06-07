Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "DeterminePackages.Helper.ps1" -Resolve)

if ([string]::IsNullOrEmpty($ENV:AL_RUNWITH)) {
    throw "You must specify runWith in setting file or use default value."
}

$settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
Get-DependenciesFromNuGet -settings $settings
Get-PreviousReleaseFromNuGet -settings $settings

Write-Host "Identifying what engine to use for packages: " $ENV:AL_RUNWITH
$runWith = ($ENV:AL_RUNWITH).ToLowerInvariant()

if ($runWith -eq 'nuget') {
    Write-Host "Using NuGet"
    . (Join-Path -Path $PSScriptRoot -ChildPath "ForNuGet\DetermineNugetPackages.ps1" -Resolve)
}
elseif ($runWith -eq 'bccontainerhelper') {
    Write-Host "Using BCContainerHelper"
    . (Join-Path -Path $PSScriptRoot -ChildPath "ForBCContainerHelper\DetermineArtifactUrl.ps1" -Resolve)
}
else {
    throw "Unknown AL_RUNWITH value: $ENV:AL_RUNWITH. Supported values are 'NuGet' and 'BCContainerHelper'."
}

if ([string]::IsNullOrEmpty($ENV:AL_ARTIFACT)) {
    throw "AL_ARTIFACT is empty. Make sure you have 'artifact' set in your settings file."
}
