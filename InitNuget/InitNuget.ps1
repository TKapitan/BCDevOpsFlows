Param()
. (Join-Path -Path $PSScriptRoot -ChildPath "InitNuget.Helper.ps1" -Resolve)

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
AddNugetPackageSource -sourceName "MSSymbols" -sourceUrl "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json"
AddNugetPackageSource -sourceName "AppSourceSymbols" -sourceUrl "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"

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

$AppFileName = (("{0}_{1}_{2}.app" -f $manifestObject.publisher, $manifestObject.name, $manifestObject.version).Split([System.IO.Path]::GetInvalidFileNameChars()) -join '')
$ParametersList = @()
$ParametersList += @(("/project:`"$baseAppFolder`" "))
$ParametersList += @(("/packagecachepath:$packageCachePath"))   
$ParametersList += @(("/out:`"{0}`"" -f "$ENV:BUILD_ARTIFACTSTAGINGDIRECTORY\$AppFileName"))
$ParametersList += @(("/loglevel:Warning"))
 
Write-Host "Using parameters:"
foreach ($Parameter in $ParametersList) {
    Write-Host "  $($Parameter)"
}
       
Push-Location

$nugetPackagePath = GetNugetPackagePath -packageName $bcDevToolsPackageName -packageVersion $bcDevToolsPackageVersion
Set-Location "$nugetPackagePath\Tools\net8.0\any"
.\alc.exe $ParametersList

Pop-Location