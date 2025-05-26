Param(
    [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $true)]
    [string] $artifact,
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default'
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Common\Import-Common.ps1" -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath "BuildWithNuget.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\ApplyAppJsonUpdates.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\WriteOutput.Helper.ps1" -Resolve)

try {
    if ($artifact -ne "////Current") {
        throw "Build with NuGet supports currently only artifact '////Current'. Currently set artifact is '$artifact'."
    }
    if ($buildMode -ne "Default") {
        throw "Build with NuGet supports currently only buildMode 'Default'. Currently set buildMode is '$buildMode'."
    }

    Assert-Prerequisites
    
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
    Update-AppJson -settings $settings -forNuGetBuild

    $baseRepoFolder = "$ENV:PIPELINE_WORKSPACE\App"
    $baseAppFolder = "$baseRepoFolder\App"
    $buildCacheFolder = "$baseRepoFolder\.buildpackages"
    $dependenciesPackageCachePath = "$baseRepoFolder\.dependencyPackages"
    if (Test-Path $dependenciesPackageCachePath) {
        $dependencies = Get-ChildItem -Path $dependenciesPackageCachePath | Where-Object { $_.Name -notlike 'Microsoft.*' }
        foreach ($dependency in $dependencies) {
            $targetPath = Join-Path $buildCacheFolder $dependency.Name
            OutputDebug -Message "Copying dependency: $($dependency.Name)"
            if (-not (Test-Path $targetPath)) {
                Copy-Item -Path $dependency.FullName -Destination $targetPath -Force -Recurse
                OutputDebug -Message "Copied dependency: $($dependency.Name)"
            }
        }
    }

    $appFileJson = Get-Content "$baseAppFolder\app.json" -Encoding UTF8 | ConvertFrom-Json

    $buildParameters = Get-BuildParameters -settings $settings -baseRepoFolder $baseRepoFolder -baseAppFolder $baseAppFolder -packageCachePath $buildCacheFolder -appFileJson $appFileJson
    $alcOutput = Invoke-AlCompiler -Parameters $buildParameters
    Write-ALCOutput -alcOutput $alcOutput -failOn $settings.failOn
}
catch {
    Write-Host "##vso[task.logissue type=error]Error while building the app with NuGet. Error message: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($_.PSMessageDetails) {
        Write-Host $_.PSMessageDetails
    }
    Write-Host "##vso[task.complete result=Failed]"
    exit 0
}