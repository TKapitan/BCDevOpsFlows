Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Common\Import-Common.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Nuget.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\WriteOutput.Helper.ps1" -Resolve)

try {
    if (!$ENV:AL_NUGETINITIALIZED) {
        throw "Nuget not initialized - make sure that the InitNuget pipeline step is configured to run before this step."
    }

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
    
    $parameters = @{}
    if ($ENV:AL_ALLOWPRERELEASE) {
        $parameters += @{
            "allowPrerelease" = $true
        }
    }

    Write-Host "Getting application package $applicationPackage"
    Get-BCDevOpsFlowsNuGetPackageToFolder -trustedNugetFeeds $trustedNuGetFeeds -packageName $applicationPackage -appSymbolsFolder $buildCacheFolder -downloadDependencies 'all' | Out-Null
    foreach ($dependency in $manifestObject.dependencies) {
        $packageName = Get-BCDevOpsFlowsNuGetPackageId -id $dependency.id -name $dependency.name -publisher $dependency.publisher
        Write-Host "Getting $($dependency.name) using name $($dependency.id)"
        Get-BCDevOpsFlowsNuGetPackageToFolder -trustedNugetFeeds $trustedNuGetFeeds -packageName $packageName -appSymbolsFolder $dependenciesPackageCachePath -downloadDependencies 'allButMicrosoft' @parameters | Out-Null
    }
    
    # XXX this is temporary workaround to merge BCContainerHelper and NuGet build steps.
    $artifact = $settings.artifact
    $ENV:AL_ARTIFACT = $artifact
    Write-Host "##vso[task.setvariable variable=AL_ARTIFACT;]$artifact"
    OutputDebug -Message "Set environment variable AL_ARTIFACT to ($ENV:AL_ARTIFACT)"
}
catch {
    Write-Host "##vso[task.logissue type=error]$($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($_.PSMessageDetails) {
        Write-Host $_.PSMessageDetails
    }
    Write-Host "##vso[task.complete result=Failed]"
    exit 0
}
