Param(
    [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $true)]
    [string] $artifact,
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default'
)

if ([string]::IsNullOrEmpty($ENV:AL_RUNWITH)) {
    throw "You must specify runWith in setting file or use default value."
}
Write-Host "Identifying what engine to use for build: " $ENV:AL_RUNWITH
$runWith = ($ENV:AL_RUNWITH).ToLowerInvariant()

try {
    $buildParameters = @{
        "artifact"  = $artifact
        "buildMode" = $buildMode
    }
    if ($runWith -eq 'nuget') {
        Write-Host "Using NuGet"
        . (Join-Path -Path $PSScriptRoot -ChildPath "WithNuGet\BuildWithNuget.ps1" -Resolve) @buildParameters
    }
    elseif ($runWith -eq 'bccontainerhelper') {
        Write-Host "Using BCContainerHelper"
        . (Join-Path -Path $PSScriptRoot -ChildPath "WithBCContainerHelper\BuildWithBCContainerHelper.ps1" -Resolve) @buildParameters
    }
}
catch {
    Write-Host "##vso[task.logissue type=error]Error while running the build using $($ENV:AL_RUNWITH). Error message: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($_.PSMessageDetails) {
        Write-Host $_.PSMessageDetails
    }
    Write-Host "##vso[task.complete result=Failed]"
    exit 0
}