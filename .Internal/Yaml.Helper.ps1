if (-not (Get-Module -Name powershell-yaml -ListAvailable)) {
    Install-Module -Name powershell-yaml -Force -Scope CurrentUser
}
Import-Module powershell-yaml

function Get-AsYamlFromFile {
    param (
        $FileName
    )

    [string[]]$fileContent = Get-Content $FileName
    return Get-AsYaml -fileContent $fileContent
}

function Get-AsYaml {
    param (
        [string[]]$fileContent
    )

    $content = $fileContent -join "`n"
    $yml = ConvertFrom-YAML $content -Ordered
    return $yml
}
 
function Write-Yaml {
    param (
        $FileName,
        $Content
    )
    $result = ConvertTo-YAML $Content
    Set-ContentLF -Path $FileName -Content $result
}