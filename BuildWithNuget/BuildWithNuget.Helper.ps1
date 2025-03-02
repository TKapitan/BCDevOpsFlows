function Assert-Prerequisites {
    if (!$ENV:AL_NUGETINITIALIZED) {
        throw "Nuget not initialized - make sure that the InitNuget pipeline step is configured to run before this step."
    }
}

function Get-BuildParameters {
    param (
        [string]$baseRepoFolder,
        [string]$baseAppFolder,
        [string]$packageCachePath,
        [object]$appFileJson
    )

    $AppFileName = (("{0}_{1}_{2}.app" -f $appFileJson.publisher, $appFileJson.name, $appFileJson.version).Split([System.IO.Path]::GetInvalidFileNameChars()) -join '')
    $outputPath = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath ".output"

    return @(
        "/project:`"$baseAppFolder`"",
        "/packagecachepath:$packageCachePath",
        "/out:`"$outputPath\$AppFileName`"",
        "/loglevel:Warning"
    )
}

function Invoke-AlCompiler {
    param([array]$Parameters)

    Write-Host "Using parameters:"
    $Parameters | ForEach-Object { Write-Host "  $_" }

    Push-Location
    try {
        Set-Location $ENV:AL_BCDEVTOOLSFOLDER
        & .\alc.exe $Parameters
    }
    finally {
        Pop-Location
    }
}