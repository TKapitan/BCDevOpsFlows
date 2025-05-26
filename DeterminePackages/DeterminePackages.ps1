Param()

if ([string]::IsNullOrEmpty($ENV:AL_RUNWITH)) {
    throw "You must specify runWith in setting file or use default value."
}
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
