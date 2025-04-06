Install-Module -Name powershell-yaml -Force -Verbose -Scope CurrentUser
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

    foreach ($line in $fileContent) { 
        $content = $content + "`n" + $line 
    }
    $yml = ConvertFrom-YAML $content
    return $yml
}
 
function Write-Yaml {
    param (
        $FileName,
        $Content
    )
    $result = ConvertTo-YAML $Content
    Set-ContentLF -Path $filePath -Value $result
}