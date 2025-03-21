Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "BuildWithNuget.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\ApplyAppJsonUpdates.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

try {
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
                Copy-Item -Path $dependency.FullName -Destination $targetPath -Force
                OutputDebug -Message "Copied dependency: $($dependency.Name)"
            }
        }
    }

    $appFileJson = Get-Content "$baseAppFolder\app.json" -Encoding UTF8 | ConvertFrom-Json

    $buildParameters = Get-BuildParameters -baseRepoFolder $baseRepoFolder -baseAppFolder $baseAppFolder -packageCachePath $buildCacheFolder -appFileJson $appFileJson
    Invoke-AlCompiler -Parameters $buildParameters
}
catch {
    Write-Host $_.Exception -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host $_.PSMessageDetails

    Write-Error "NuGet build failed. See previous lines for details."
}
