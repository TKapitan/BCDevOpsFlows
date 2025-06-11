Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "DeterminePackages.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

if ([string]::IsNullOrEmpty($ENV:AL_RUNWITH)) {
    throw "You must specify runWith in setting file or use default value."
}

# Update settings from app configuration
$settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
$settings = Update-CustomCodeCops -settings $settings
$settings = Get-DependenciesFromNuGet -settings $settings
$settings = Get-PreviousReleaseFromNuGet -settings $settings

# Set output variables
$ENV:AL_SETTINGS = $($settings | ConvertTo-Json -Depth 99 -Compress)
Write-Host "##vso[task.setvariable variable=AL_SETTINGS;]$($settings | ConvertTo-Json -Depth 99 -Compress)"
OutputDebug -Message "Set environment variable AL_SETTINGS to ($ENV:AL_SETTINGS)"

# Determine packages
Write-Host "Identifying what engine to use for packages: " $ENV:AL_RUNWITH
$runWith = ($ENV:AL_RUNWITH).ToLowerInvariant()

. (Join-Path -Path $PSScriptRoot -ChildPath "ForNuGet\DetermineNugetPackages.ps1" -Resolve) -appFolder "App"

if ($runWith -eq 'nuget') {
    Write-Host "Using NuGet"
    # No special steps needed
}
elseif ($runWith -eq 'bccontainerhelper') {
    Write-Host "Using BCContainerHelper"
    
    # Tests are supported only in BCC, find test app dependencies
    . (Join-Path -Path $PSScriptRoot -ChildPath "ForNuGet\DetermineNugetPackages.ps1" -Resolve) -appFolder "Test"
    # Find BCC artifact
    . (Join-Path -Path $PSScriptRoot -ChildPath "ForBCContainerHelper\DetermineArtifactUrl.ps1" -Resolve)
}
else {
    throw "Unknown AL_RUNWITH value: $ENV:AL_RUNWITH. Supported values are 'NuGet' and 'BCContainerHelper'."
}

if ([string]::IsNullOrEmpty($ENV:AL_ARTIFACT)) {
    throw "AL_ARTIFACT is empty. Make sure you have 'artifact' set in your settings file."
}
