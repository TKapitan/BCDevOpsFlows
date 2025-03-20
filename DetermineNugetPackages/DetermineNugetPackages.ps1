Param()
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Nuget.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

if (!$ENV:AL_NUGETINITIALIZED) {
    Write-Error "Nuget not initialized - make sure that the InitNuget pipeline step is configured to run before this step."
}

try {
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json

    AddNugetPackageSource -sourceName "MSSymbols" -sourceUrl "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json"
    AddNugetPackageSource -sourceName "AppSourceSymbols" -sourceUrl "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"

    $baseRepoFolder = "$ENV:PIPELINE_WORKSPACE\App"
    $baseAppFolder = "$baseRepoFolder\App"

    $applicationPackage = "Microsoft.Application.symbols"
    if ($settings.country) {
        $applicationPackage = "Microsoft.Application.$($settings.country.ToUpper()).symbols"
    }
    $manifestObject = Get-Content "$baseAppFolder\app.json" -Encoding UTF8 | ConvertFrom-Json
 
    $packageCachePath = "$baseRepoFolder\.alpackages"
    mkdir $packageCachePath
 
    nuget install $applicationPackage -outputDirectory $packageCachePath 
    foreach ($Dependency in $manifestObject.dependencies | Where-Object { -not ($_.publisher -eq "Microsoft" -and $_.name.StartsWith("_Exclude")) }) {
        $PackageName = ("{0}.{1}.symbols.{2}" -f $Dependency.publisher, $Dependency.name, $Dependency.id ) -replace ' ', ''
        Write-Host "Get $PackageName"
         
        nuget install $PackageName -outputDirectory $packageCachePath 
    }
}
catch {
    Write-Host $_.Exception -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host $_.PSMessageDetails

    Write-Error "Process failed. See previous lines for details."
}
