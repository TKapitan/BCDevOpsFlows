function GetDependencyVersionFilter {
    Param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $appJson,
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $dependency
    )
    return ""
}