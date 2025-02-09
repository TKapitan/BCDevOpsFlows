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

$bcDevToolsPackageName = "Microsoft.Dynamics.BusinessCentral.Development.Tools"
$bcDevToolsPackageVersion = $settings.nugetBCDevToolsVersion

DownloadNugetPackage -packageName $bcDevToolsPackageName -packageVersion $bcDevToolsPackageVersion

$bcDevToolsFolder = Join-Path -Path (GetNugetPackagePath -packageName $bcDevToolsPackageName -packageVersion $bcDevToolsPackageVersion) -ChildPath "Tools\net8.0\any"
$ENV:AL_BCDEVTOOLSFOLDER = $bcDevToolsFolder
Write-Host "##vso[task.setvariable variable=AL_BCDEVTOOLSFOLDER;]$bcDevToolsFolder"
OutputDebug -Message "Set environment variable AL_BCDEVTOOLSFOLDER to ($ENV:AL_BCDEVTOOLSFOLDER)"

$ENV:AL_NUGETINITIALIZED = $true
Write-Host "##vso[task.setvariable variable=AL_NUGETINITIALIZED;]$true"
OutputDebug -Message "Set environment variable AL_NUGETINITIALIZED to ($ENV:AL_NUGETINITIALIZED)"
