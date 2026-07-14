. (Join-Path -Path $PSScriptRoot -ChildPath "Common\Get-AppJson.ps1" -Resolve)

function Get-AppSourceFileLocation {
    [CmdletBinding()]
    Param (
        $appFile
    )

    return (Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath ".output") + '\' + (Get-AppFileName -publisher $appFile.publisher -name $appFile.name -version $appFile.version);
}
function Get-AppFileName {
    [CmdletBinding()]
    Param (
        [string]$publisher,
        [string]$name,
        [string]$version
    )

    $appFileName = $publisher + '_' + $name + '_' + $version + '.app'
    $sanitizedAppFileName = $appFileName -replace '[\\/:*?"<>|]', ''
    return $sanitizedAppFileName
}