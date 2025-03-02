. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\FindDependencies.Helper.ps1" -Resolve)

function Get-AppTargetFilePathForNewApp {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string] $writableFolderPath,
        [Parameter(Mandatory)]
        $appFileJson,
        [switch] $isPreview
    )

    $releaseTypeFolderParam = @{}
    if ($isPreview -eq $true) {
        $releaseTypeFolderParam = @{ "isPreview" = $true }
    }
    
    $releaseTypeFolder = Get-ReleaseTypeFolderName @releaseTypeFolderParam
    $targetFilePath = "$writableFolderPath\apps\$releaseTypeFolder\$($appFileJson.id)\$($appFileJson.version)-BC$($appFileJson.application)\"
    Write-Host "Using '$targetFilePath' regardless if the extension exists or not"
    return $targetFilePath
}