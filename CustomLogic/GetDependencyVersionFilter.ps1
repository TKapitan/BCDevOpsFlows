function GetDependencyVersionFilter {
    Param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $appJson,
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $dependency
    )
    if ($dependency.publisher.Replace(' ', '') -eq 'Microsoft') {
        Write-Host "Dependency $($dependency.name) is from Microsoft, no version filter applied."
        return ""
    }
    if ($appJson.publisher.Replace(' ', '') -ne $dependency.publisher.Replace(' ', '')) {
        Write-Host "Dependency $($dependency.name) is from different publisher ($($dependency.publisher)) than the main app ($($appJson.publisher)), using exact version match."
        return "[$($dependency.version)]"
    }
    $versionParts = $appJson.application.Split('.')
    $versionParts[1] = ([int]$versionParts[1] + 1).ToString().PadLeft(2, '0')
    Write-Host "Dependency $($dependency.name) is from the same publisher ($($dependency.publisher)) as the main app ($($appJson.publisher)), using version range [$($dependency.version),$($versionParts[0])$($versionParts[1]).0.0.0)."
    return "[$($dependency.version),$($versionParts[0])$($versionParts[1]).0.0.0)"
}