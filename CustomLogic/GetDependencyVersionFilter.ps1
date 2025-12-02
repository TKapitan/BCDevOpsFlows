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
    if ($ENV:AL_PIPELINENAME -eq "TestNextMajor") {
        Write-Host "Calculating next major version for dependency $($dependency.name)."
        $versionParts[0] = [int]$versionParts[0] + 1
        $versionParts[1] = '01'
    }
    elseif ($ENV:AL_PIPELINENAME -eq "TestNextMinor") {
        Write-Host "Calculating next minor version for dependency $($dependency.name)."
        $versionParts[1] = ([int]$versionParts[1] + 2).ToString().PadLeft(2, '0')
    }
    else {
        $versionParts[1] = ([int]$versionParts[1] + 1).ToString().PadLeft(2, '0')
    }
    Write-Host "Dependency $($dependency.name) is from the same publisher ($($dependency.publisher)) as the main app ($($appJson.publisher)), using version range [$($dependency.version),$($versionParts[0])$($versionParts[1]).0.0.0)."
    return "[$($dependency.version),$($versionParts[0])$($versionParts[1]).0.0.0)"
}