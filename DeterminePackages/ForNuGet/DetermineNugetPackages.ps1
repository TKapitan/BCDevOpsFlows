Param(
    [Parameter(Mandatory = $false)]
    [string] $appFolder = "App"
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Common\Import-Common.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Nuget.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\WriteOutput.Helper.ps1" -Resolve)

try {
    if (!$ENV:AL_NUGETINITIALIZED) {
        throw "Nuget not initialized - make sure that the InitNuget pipeline step is configured to run before this step."
    }

    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json
    $baseRepoFolder = "$ENV:PIPELINE_WORKSPACE\App"
    $baseAppFolder = "$baseRepoFolder\$appFolder"

    $applicationPackage = "Microsoft.Application.symbols"
    if ($settings.country) {
        $applicationPackage = "Microsoft.Application.$($settings.country.ToUpper()).symbols"
    }
    $appJsonContent = Get-Content "$baseAppFolder\app.json" -Encoding UTF8 | ConvertFrom-Json
 
    $buildCacheFolder = "$baseRepoFolder\.buildpackages"
    if (!(Test-Path $buildCacheFolder)) {
        New-Item -Path $buildCacheFolder -ItemType Directory | Out-Null
    }
    $dependenciesPackageCachePath = "$baseRepoFolder\.buildartifacts\Dependencies"
    if (!(Test-Path $dependenciesPackageCachePath)) {
        New-Item -Path $dependenciesPackageCachePath -ItemType Directory | Out-Null
    }

    $artifact = $settings.artifact
    Write-Host "Getting application package $applicationPackage for artifact $artifact"
    
    # Init application/platform parameters
    if ($ENV:AL_RUNWITH -eq "NuGet") {
        $trustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -includeMicrosoftNuGetFeeds -trustMicrosoftNuGetFeeds $settings.trustMicrosoftNuGetFeeds
        $parameters = @{
            "trustedNugetFeeds"    = $trustedNuGetFeeds
            "packageName"          = $applicationPackage
            "appSymbolsFolder"     = $buildCacheFolder
            "downloadDependencies" = "Microsoft"
            "select"               = "Latest"
        }

        $isAppJsonArtifact = $artifact.ToLower() -eq "////appjson"
        if ($artifact.ToLower() -eq "////latest") {
            Get-BCDevOpsFlowsNuGetPackageToFolder @parameters | Out-Null
        } 
        elseif ($isAppJsonArtifact) {
            $versionParts = $appJsonContent.application.Split('.')
            $versionParts[1] = ([int]$versionParts[1] + 1).ToString()
            $version = "[$($appJsonContent.application),$($versionParts[0]).$($versionParts[1]).$($versionParts[2]).$($versionParts[3]))"
            $parameters += @{
                "version" = $version
            }
            Get-BCDevOpsFlowsNuGetPackageToFolder @parameters | Out-Null
        }
        else {
            throw "Invalid artifact setting ($artifact) in app.json. The artifact can only be '////latest' or '////appJson'."
        }
        $ENV:AL_APPJSONARTIFACT = $isAppJsonArtifact
        Write-Host "##vso[task.setvariable variable=AL_APPJSONARTIFACT;]$isAppJsonArtifact"
        OutputDebug -Message "Set environment variable AL_APPJSONARTIFACT to ($ENV:AL_APPJSONARTIFACT)"
    }

    # Init dependency parameters
    $trustedNuGetFeeds = Get-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL
    $parameters = @{
        "trustedNugetFeeds"    = $trustedNuGetFeeds
        "appSymbolsFolder"     = $dependenciesPackageCachePath
        "downloadDependencies" = "allButMicrosoft"
    }
    if ($ENV:AL_ALLOWPRERELEASE) {
        $parameters += @{
            "allowPrerelease" = $true
        }
    }
    foreach ($dependency in $appJsonContent.dependencies) {
        $packageName = Get-BCDevOpsFlowsNuGetPackageId -id $dependency.id -name $dependency.name -publisher $dependency.publisher
        Write-Host "Getting $($dependency.name) using name $($dependency.id)"
        Get-BCDevOpsFlowsNuGetPackageToFolder -packageName $packageName @parameters | Out-Null
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
