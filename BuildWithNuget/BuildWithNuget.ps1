if (!$ENV:AL_NUGETINITIALIZED) {
    Write-Error "Nuget not initialized - make sure that the InitNuget pipeline step is configured to run before this step."
}

$baseRepoFolder = "$ENV:PIPELINE_WORKSPACE\App"
$baseAppFolder = "$baseRepoFolder\App"
$packageCachePath = "$baseRepoFolder\.alpackages"
$appFileJson = Get-Content "$baseAppFolder\app.json" -Encoding UTF8 | ConvertFrom-Json

$AppFileName = (("{0}_{1}_{2}.app" -f $appFileJson.publisher, $appFileJson.name, $appFileJson.version).Split([System.IO.Path]::GetInvalidFileNameChars()) -join '')
$ParametersList = @()
$ParametersList += @(("/project:`"$baseAppFolder`" "))
$ParametersList += @(("/packagecachepath:$packageCachePath"))   
$ParametersList += @(("/out:`"{0}`"" -f "$(Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath ".output")\$AppFileName"))
$ParametersList += @(("/loglevel:Warning"))
 
Write-Host "Using parameters:"
foreach ($Parameter in $ParametersList) {
    Write-Host "  $($Parameter)"
}
       
Push-Location
Set-Location $ENV:AL_BCDEVTOOLSFOLDER
.\alc.exe $ParametersList
Pop-Location
