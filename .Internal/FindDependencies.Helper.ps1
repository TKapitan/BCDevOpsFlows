function Get-AppJsonFile {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string] $sourceAppJsonFilePath
    ) 

    ## Find app.json
    $appFile = '';
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $encoding = 'utf8'
        $PSDefaultParameterValues['*:Encoding'] = $encoding
    }
    else {
        $encoding = 'UTF8'
        $PSDefaultParameterValues['*:Encoding'] = $encoding
    }
    foreach ($appFilePath in $sourceAppJsonFilePath) {
        if (Test-Path -Path $appFilePath -PathType Leaf) {
            OutputDebug -Message "Trying to load json file: $appFilePath"
            $appFile = (Get-Content $appFilePath -Encoding $encoding | ConvertFrom-Json);
            break;
        }
    }
    if ($appFile -eq '') {
        throw "App.json file was not found for $($sourceAppJsonFilePath).";
    }
    else {
        OutputDebug -Message "App.json found for $($appFilePath)"
    }
    return $appFile;
}
function Get-AppSourceFileLocation {
    [CmdletBinding()]
    Param (
        $appFile
    )

    return (Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath ".output") + '/' + (Get-AppFileName -publisher $appFile.publisher -name $appFile.name -version $appFile.version);
}
function Get-AppFileName {
    [CmdletBinding()]
    Param (
        [string]$publisher,
        [string]$name,
        [string]$version
    )

    return $publisher + '_' + $name + '_' + $version + '.app';
}