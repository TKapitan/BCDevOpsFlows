Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "BuildWithNuget.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\ApplyAppJsonUpdates.Helper.ps1" -Resolve)

try {
    Assert-Prerequisites
    
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
    Update-AppJson -settings $settings -forNuGetBuild

    $baseRepoFolder = "$ENV:PIPELINE_WORKSPACE\App"
    $baseAppFolder = "$baseRepoFolder\App"
    $packageCachePath = "$baseRepoFolder\.alpackages"
    $dependenciesCachePath = "$baseRepoFolder\.buildartifacts\Dependencies"
    if (Test-Path $dependenciesCachePath) {
        $dependencies = Get-ChildItem -Path $dependenciesCachePath -Filter "*.app"
        foreach ($dependency in $dependencies) {
            $targetPath = Join-Path $packageCachePath $dependency.Name
            if (-not (Test-Path $targetPath)) {
                Copy-Item -Path $dependency.FullName -Destination $targetPath -Force
            }
        }
    }
    $appFileJson = Get-Content "$baseAppFolder\app.json" -Encoding UTF8 | ConvertFrom-Json

    $buildParameters = Get-BuildParameters -baseRepoFolder $baseRepoFolder -baseAppFolder $baseAppFolder -packageCachePath $packageCachePath -appFileJson $appFileJson
    Invoke-AlCompiler -Parameters $buildParameters
}
catch {
    Write-Host $_.Exception -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host $_.PSMessageDetails

    Write-Error "NuGet build failed. See previous lines for details."
}
