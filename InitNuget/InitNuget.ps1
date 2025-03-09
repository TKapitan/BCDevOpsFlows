Param()
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Nuget.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

$settings = $ENV:AL_SETTINGS | ConvertFrom-Json
if (!$settings) {
    Write-Error "Settings not found - make sure that the ReadSettings pipeline step is configured to run before this step."
}
if (!$settings.nugetBCDevToolsVersion) {
    Write-Error "Nuget package version not found in settings file. Do not specify 'nugetBCDevToolsVersion' in setting files to use the default version."
}

DownloadAndImportBcContainerHelper

$bcDevToolsPackageName = "Microsoft.Dynamics.BusinessCentral.Development.Tools"
$bcDevToolsPackageVersion = $settings.nugetBCDevToolsVersion

DownloadNugetPackage -packageName $bcDevToolsPackageName -packageVersion $bcDevToolsPackageVersion

$bcContainerHelperConfig.TrustedNuGetFeeds = @()
if ($ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL) {
    $trustedNuGetFeeds = $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL | ConvertFrom-Json
    if ($trustedNuGetFeeds -and $trustedNuGetFeeds.Count -gt 0) {
        Write-Host "Adding trusted NuGet feeds from environment variable"
        $trustedNuGetFeeds = @($trustedNuGetFeeds | ForEach-Object {
            $feedConfig = New-NuGetFeedConfig -url $_.serverUrl -token $_.token
            $bcContainerHelperConfig.TrustedNuGetFeeds += @($feedConfig)
        })
    }
}
if ($settings.trustMicrosoftNuGetFeeds) {
    $feedConfig = New-NuGetFeedConfig -url "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"
    $bcContainerHelperConfig.TrustedNuGetFeeds += @($feedConfig)
}

$bcDevToolsFolder = Join-Path -Path (GetNugetPackagePath -packageName $bcDevToolsPackageName -packageVersion $bcDevToolsPackageVersion) -ChildPath "Tools\net8.0\any"
$ENV:AL_BCDEVTOOLSFOLDER = $bcDevToolsFolder
Write-Host "##vso[task.setvariable variable=AL_BCDEVTOOLSFOLDER;]$bcDevToolsFolder"
OutputDebug -Message "Set environment variable AL_BCDEVTOOLSFOLDER to ($ENV:AL_BCDEVTOOLSFOLDER)"

$ENV:AL_NUGETINITIALIZED = $true
Write-Host "##vso[task.setvariable variable=AL_NUGETINITIALIZED;]$true"
OutputDebug -Message "Set environment variable AL_NUGETINITIALIZED to ($ENV:AL_NUGETINITIALIZED)"
