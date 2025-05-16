function Assert-Prerequisites {
    if (!$ENV:AL_NUGETINITIALIZED) {
        throw "Nuget not initialized - make sure that the InitNuget pipeline step is configured to run before this step."
    }
}

function Get-BuildParameters {
    param (
        $settings,
        [string]$baseRepoFolder,
        [string]$baseAppFolder,
        [string]$packageCachePath,
        [object]$appFileJson
    )

    $AppFileName = (("{0}_{1}_{2}.app" -f $appFileJson.publisher, $appFileJson.name, $appFileJson.version).Split([System.IO.Path]::GetInvalidFileNameChars()) -join '')
    $outputPath = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath ".output"

    $alcItem = Get-Item -Path (Join-Path $ENV:AL_BCDEVTOOLSFOLDER 'alc.exe')
    [System.Version]$alcVersion = $alcItem.VersionInfo.FileVersion
    $alcParameters = @(
        "/project:""$baseAppFolder""", 
        "/packagecachepath:""$packageCachePath""", 
        "/out:""$outputPath\$AppFileName""",
        "/loglevel:Warning"
    )
    if ($alcVersion -ge [System.Version]"12.0.12.41479") {
        $alcParameters = @(
            "sourceRepositoryUrl:""$ENV:BUILD_REPOSITORY_URI""",
            "sourceCommit:""$ENV:BUILD_SOURCEVERSION""",
            "buildBy:""BCDevOpsFlows""",
            "buildUrl:""$ENV:BUILD_BUILDURI"""
        )
    }
    if ($settings.ContainsKey('preprocessorSymbols')) {
        Write-Host "Adding Preprocessor symbols : $($settings.preprocessorSymbols -join ',')"
        $settings.preprocessorSymbols | where-Object { $_ } | ForEach-Object { $alcParameters += @("/D:$_") }
    }
    return $alcParameters
}

function Invoke-AlCompiler {
    param(
        [array]$Parameters
    )

    Write-Host "Using parameters:"
    $Parameters | ForEach-Object { Write-Host "  $_" }

    Push-Location
    try {
        Write-Host ".\alc.exe $([string]::Join(' ', $Parameters))"
        Set-Location $ENV:AL_BCDEVTOOLSFOLDER
        & .\alc.exe $Parameters
    }
    finally {
        Pop-Location
    }
}