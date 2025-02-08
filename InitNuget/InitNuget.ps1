Param()
. (Join-Path -Path $PSScriptRoot -ChildPath "InitNuget.Helper.ps1" -Resolve)

$settings = $ENV:AL_SETTINGS
if ($settings.nugetBCDevToolsVersion -eq '') {
    Write-Error "Nuget package version not found in settings file. Do not specify 'nugetBCDevToolsVersion' in setting files to use the default version."
}
DownloadNugetPackage -packageName "Microsoft.Dynamics.BusinessCentral.Development.Tools" -packageVersion $settings.nugetBCDevToolsVersion

nuget source add -Name MSSymbols -source "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json"
nuget source add -Name AppSourceSymbols -source "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"  

$ApplicationPackage = "Microsoft.Application.symbols"
$ManifestObject = Get-Content $(Build.SourcesDirectory)\app\app.json -Encoding UTF8 | ConvertFrom-Json
$applicationVersion = $ManifestObject.Application 
 
$packagecachepath = "$(Agent.BuildDirectory)\alpackages"
mkdir $packagecachepath
 
nuget install $ApplicationPackage -version $applicationVersion -outputDirectory $packagecachepath 
 
foreach ($Dependency in $ManifestObject.dependencies) {
    $PackageName = ("{0}.{1}.symbols.{2}" -f $Dependency.publisher, $Dependency.name, $Dependency.id ) -replace ' ', ''
    Write-Host "Get $PackageName"
         
    nuget install $PackageName -version $Dependency.version -outputDirectory $packagecachepath 
}

$ManifestObject = Get-Content $(Build.SourcesDirectory)\app\app.json -Encoding UTF8 | ConvertFrom-Json
$packagecachepath = "$(Agent.BuildDirectory)\alpackages"
$ParametersList = @()
$AppFileName = (("{0}_{1}_{2}.app" -f $ManifestObject.publisher, $ManifestObject.name, $ManifestObject.version).Split([System.IO.Path]::GetInvalidFileNameChars()) -join '')
$ParametersList += @(("/project:`"$(Build.SourcesDirectory)\app`" "))
$ParametersList += @(("/packagecachepath:$packagecachepath"))   
$ParametersList += @(("/out:`"{0}`"" -f "$(Build.ArtifactStagingDirectory)\$AppFileName"))
$ParametersList += @(("/loglevel:Warning"))
 
Write-Host "Using parameters:"
foreach ($Parameter in $ParametersList) {
    Write-Host "  $($Parameter)"
}
       
Push-Location
Set-Location .\alc\Tools\net8.0\any
.\alc.exe $ParametersList
Pop-Location