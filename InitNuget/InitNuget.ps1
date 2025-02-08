Param()
. (Join-Path -Path $PSScriptRoot -ChildPath "InitNuget.Helper.ps1" -Resolve)
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

InstallAndRegisterNugetPackageProvider
DownloadNugetPackage -packageName $bcDevToolsPackageName -packageVersion $bcDevToolsPackageVersion
AddNugetPackageSource -sourceName "MSSymbols" -sourceUrl "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json"
AddNugetPackageSource -sourceName "AppSourceSymbols" -sourceUrl "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"

$bcDevToolsFolder = Join-Path -Path (GetNugetPackagePath -packageName $bcDevToolsPackageName -packageVersion $bcDevToolsPackageVersion) -ChildPath "Tools\net8.0\any"
$ENV:AL_BCDEVTOOLSFOLDER = $bcDevToolsFolder
Write-Host "##vso[task.setvariable variable=AL_BCDEVTOOLSFOLDER;]$bcDevToolsFolder"
OutputDebug -Message "Set environment variable AL_BCDEVTOOLSFOLDER to ($ENV:AL_BCDEVTOOLSFOLDER)"

$baseRepoFolder = "$ENV:PIPELINE_WORKSPACE\App"
$baseAppFolder = "$baseRepoFolder\App"

$applicationPackage = "Microsoft.Application.symbols"
$manifestObject = Get-Content "$baseAppFolder\app.json" -Encoding UTF8 | ConvertFrom-Json
 
$packageCachePath = "$baseRepoFolder\.alpackages"
mkdir $packageCachePath
 
nuget install $applicationPackage -outputDirectory $packageCachePath 
 
foreach ($Dependency in $manifestObject.dependencies) {
    $PackageName = ("{0}.{1}.symbols.{2}" -f $Dependency.publisher, $Dependency.name, $Dependency.id ) -replace ' ', ''
    Write-Host "Get $PackageName"
         
    nuget install $PackageName -outputDirectory $packageCachePath 
}

$ENV:AL_NUGETINITIALIZED = $true
Write-Host "##vso[task.setvariable variable=AL_NUGETINITIALIZED;]$true"
OutputDebug -Message "Set environment variable AL_NUGETINITIALIZED to ($ENV:AL_NUGETINITIALIZED)"
