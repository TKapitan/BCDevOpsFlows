Param()
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Nuget.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

if (!$ENV:AL_NUGETINITIALIZED) {
    Write-Error "Nuget not initialized - make sure that the InitNuget pipeline step is configured to run before this step."
}

try {
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json

    # Initialize trusted NuGet feeds
    $TrustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL -trustMicrosoftNuGetFeeds $settings.trustMicrosoftNuGetFeeds
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json  
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
 
    $packageCachePath = "$baseRepoFolder\.alpackages"
    mkdir $packageCachePath

    nuget install $applicationPackage -outputDirectory $packageCachePath 
    foreach ($Dependency in $manifestObject.dependencies) {
        $PackageName = Get-BcNugetPackageId -id $Dependency.id -name $Dependency.name -publisher $Dependency.publisher
        Write-Host "Geting package $PackageName"

        $found = $false
        foreach ($feed in $TrustedNuGetFeeds) {
            try {
                nuget install $PackageName -Source $feed.url -OutputDirectory $packageCachePath -NonInteractive -Verbosity detailed
                OutputDebug -Message "Package $PackageName found in feed $($feed.Name)"
                $found = $true
                break
            }
            catch {
                Write-Host "Package $package not found in feed $($feed.Name)"
            }
        }
        if (-Not $found) {
            Write-Error "Package $package not found in any feed"
        }
    }
}
catch {
    Write-Host $_.Exception -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host $_.PSMessageDetails

    Write-Error "Process failed. See previous lines for details."
}
