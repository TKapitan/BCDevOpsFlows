Param(
    [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $true)]
    [string] $artifact = "",
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default',
    [Parameter(HelpMessage = "Specifies whether to allow prerelease/preview apps as dependencies.", Mandatory = $false)]
    [switch] $allowPrerelease
)

if ([string]::IsNullOrEmpty($ENV:AL_RUNWITH)) {
    throw "You must specify runWith in setting file or use default value."
}
Write-Host "Identifying what engine to use for build: " $ENV:AL_RUNWITH
$runWith = ($ENV:AL_RUNWITH).ToLowerInvariant()

$buildParameters = @{
    "artifact"  = $artifact
    "buildMode" = $buildMode
}
if ($allowPrerelease) {
    $buildParameters += @{
        "allowPrerelease" = $true
    }
}

if ($runWith -eq 'nuget') {
    Write-Host "Using NuGet"
    . (Join-Path -Path $PSScriptRoot -ChildPath "WithNuGet\BuildWithNuget.ps1" -Resolve) @buildParameters
}
elseif ($runWith -eq 'bccontainerhelper') {
    Write-Host "Using BCContainerHelper"
    . (Join-Path -Path $PSScriptRoot -ChildPath "WithBCContainerHelper\BuildWithBCContainerHelper.ps1" -Resolve) @buildParameters
}
