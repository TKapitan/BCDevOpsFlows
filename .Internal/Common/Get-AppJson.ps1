. (Join-Path -Path $PSScriptRoot -ChildPath "..\WriteOutput.Helper.ps1" -Resolve)

# Canonical app.json reader. Both entry points share the same read logic (UTF-8, raw read,
# single parse) so every step sees identical parsing behavior on both PowerShell editions.

function Get-AppJsonFile {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string] $sourceAppJsonFilePath
    )

    if (-not (Test-Path -Path $sourceAppJsonFilePath -PathType Leaf)) {
        throw "App.json file was not found for $($sourceAppJsonFilePath)."
    }
    OutputDebug -Message "Loading json file: $sourceAppJsonFilePath"
    return (Get-Content -Path $sourceAppJsonFilePath -Encoding UTF8 -Raw | ConvertFrom-Json)
}

function Get-AppJson {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $settings
    )

    $folder = Join-Path "$ENV:PIPELINE_WORKSPACE/App" $settings.appFolders[0]
    $appJsonFile = Join-Path $folder "app.json"
    if (-not (Test-Path $appJsonFile)) {
        throw "No app.json file found in $folder"
    }
    return Get-AppJsonFile -sourceAppJsonFilePath $appJsonFile
}
