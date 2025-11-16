function Get-AppJson {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $settings
    )

    $folder = Join-Path "$ENV:PIPELINE_WORKSPACE/App" $settings.appFolders[0]
    $appJsonFile = Join-Path $folder "app.json"
    if (Test-Path $appJsonFile) {
        $appJson = Get-Content $appJsonFile -Encoding UTF8 -Raw | ConvertFrom-Json 
        return $appJson
    }
    else {
        throw  "No app.json file found in $folder"
    }
}
