Param(
    [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $true)]
    [string] $artifact = "",
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default',
    [Parameter(HelpMessage = "A JSON-formatted list of apps to install", Mandatory = $false)]
    [string] $installAppsJson = '[]',
    [Parameter(HelpMessage = "A JSON-formatted list of test apps to install", Mandatory = $false)]
    [string] $installTestAppsJson = '[]',
    [Parameter(HelpMessage = "Specifies whether to skip preview apps as dependencies.", Mandatory = $false)]
    [switch] $skipAppsInPreview
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
Write-Host "!!!!!!!!!!!!!!!This step will be removed in July 2025. Use generic step 'Build' instead!!!!!!!!!!!!!!!"
Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

# Set default value for backwards compatibility
$buildParameters = @{
    "artifact"  = $artifact
    "buildMode" = $buildMode
}
$allowPrerelease = -not $skipAppsInPreview
$ENV:AL_ALLOWPRERELEASE = $allowPrerelease
Write-Host "##vso[task.setvariable variable=AL_ALLOWPRERELEASE;]$allowPrerelease"
Write-Host "Set environment variable AL_ALLOWPRERELEASE to ($ENV:AL_ALLOWPRERELEASE)"
if ($installAppsJson -ne '[]' -or $installTestAppsJson -ne '[]') {
    throw "$installAppsJson and $installTestAppsJson parameters are no longer supported"
}

# Set runner type for backwards compatibility
$settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
if (-not $settings.ContainsKey('runWith')) {
    $settings.Add('runWith', 'BCContainerHelper')
} else {
    $settings.runWith = 'BCContainerHelper'
}
$ENV:AL_SETTINGS = $($settings | ConvertTo-Json -Depth 99 -Compress)
Write-Host "##vso[task.setvariable variable=AL_SETTINGS;]$($settings | ConvertTo-Json -Depth 99 -Compress)"
OutputDebug -Message "Set environment variable AL_SETTINGS to ($ENV:AL_SETTINGS)"
$ENV:AL_RUNWITH = 'BCContainerHelper'
Write-Host "##vso[task.setvariable variable=AL_RUNWITH;]BCContainerHelper"
OutputDebug -Message "Set environment variable AL_RUNWITH to ($ENV:AL_RUNWITH)"

# Run
. (Join-Path -Path $PSScriptRoot -ChildPath "..\Build\Build.ps1" -Resolve) @buildParameters
