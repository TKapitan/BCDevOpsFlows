Param()
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Nuget.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

if (!$ENV:AL_NUGETINITIALIZED) {
    Write-Error "Nuget not initialized - make sure that the InitNuget pipeline step is configured to run before this step."
}

try {
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json
    $TrustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL -trustMicrosoftNuGetFeeds $settings.trustMicrosoftNuGetFeeds
    foreach ($feed in $TrustedNuGetFeeds) {
        Add-NugetPackageSource -feed $feed
    }

    $baseRepoFolder = "$ENV:PIPELINE_WORKSPACE\App"
    $baseAppFolder = "$baseRepoFolder\App"

    $applicationPackage = "Microsoft.Application.symbols"
    if ($settings.country) {
        $applicationPackage = "Microsoft.Application.$($settings.country.ToUpper()).symbols"
    }
    $manifestObject = Get-Content "$baseAppFolder\app.json" -Encoding UTF8 | ConvertFrom-Json
 
    $buildCacheFolder = "$baseRepoFolder\.buildpackages"
    mkdir $buildCacheFolder
    $dependenciesPackageCachePath = "$baseRepoFolder\.dependencyPackages"
    mkdir $dependenciesPackageCachePath
    
    nuget install $applicationPackage -outputDirectory $buildCacheFolder 
    foreach ($Dependency in $manifestObject.dependencies) {
        $PackageName = Get-BcNugetPackageId -id $Dependency.id -name $Dependency.name -publisher $Dependency.publisher
        Write-Host "Get $PackageName"
        nuget install $PackageName -outputDirectory $dependenciesPackageCachePath
    }
}
catch {
    Write-Host $_.Exception -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host $_.PSMessageDetails

    Write-Error "Process failed. See previous lines for details."
}
