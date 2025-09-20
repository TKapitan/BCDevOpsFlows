function GetDependencyVersionFilter {
    Param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $appJson,
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $dependency
    )
    if ($dependency.publisher -eq 'Microsoft') {
        return ""
    }
    if ($appJson.publisher -ne $dependency.publisher) {
        return "[$($dependency.version)]"
    }
    $versionParts = $appJson.application.Split('.')
    $versionParts[1] = ([int]$versionParts[1] + 1).ToString().PadLeft(2, '0')
    return "[$($dependency.version),$($versionParts[0])$($versionParts[1]).0.0.0)"
}