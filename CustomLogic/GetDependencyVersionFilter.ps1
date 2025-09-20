function GetDependencyVersionFilter {
    Param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $appJson,
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $dependency
    )
    if ($appJson.publisher -ne $dependency.publisher) {
        return "" # Use standard logic
    }
    $versionParts = $appJson.application.Split('.')
    $versionParts[1] = ([int]$versionParts[1] + 1).ToString()
    return "[$($dependency.version),$($versionParts[0])$($versionParts[1]).0.0.0)"
}