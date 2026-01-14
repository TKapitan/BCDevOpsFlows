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
        if($null -eq $($dependency.version) -or $($dependency.version) -eq '') {
            Write-Host "Dependency $($dependency.name) does not have a version specified, cannot apply version filter."
            return ""
        }
        Write-Host "Dependency $($dependency.name) is from different publisher ($($dependency.publisher)) than the main app ($($appJson.publisher)), using exact version match."
        return "[$($dependency.version)]"
    }
    $versionParts = $appJson.application.Split('.')
    if ($ENV:AL_PIPELINENAME -eq "TestNextMajor") {
        Write-Host "Calculating next major version for dependency $($dependency.name)."
        $versionParts[0] = $ENV:AL_BCMAJORVERSION + 1
        $versionParts[1] = '01'
    }
    elseif ($ENV:AL_PIPELINENAME -eq "TestNextMinor") {
        Write-Host "Calculating next minor version for dependency $($dependency.name)."
        $versionParts[0] = $ENV:AL_BCMAJORVERSION
        $versionParts[1] = ([int]$ENV:AL_BCMINORVERSION + 2).ToString().PadLeft(2, '0')
    }
    elseif ($ENV:AL_PIPELINENAME -eq "TestCurrent") {
        Write-Host "Calculating current version for dependency $($dependency.name)."
        $versionParts[0] = $ENV:AL_BCMAJORVERSION
        $versionParts[1] = ([int]$ENV:AL_BCMINORVERSION + 1).ToString().PadLeft(2, '0')
    }
    else {
        $versionParts[1] = ([int]$versionParts[1] + 1).ToString().PadLeft(2, '0')
    }
    if($null -eq $($dependency.version) -or $($dependency.version) -eq '') {
        Write-Host "Dependency $($dependency.name) does not have a version specified, using version range (,$($versionParts[0])$($versionParts[1]).0.0.0)."
        return "(,$($versionParts[0])$($versionParts[1]).0.0.0)"
    }
    Write-Host "Dependency $($dependency.name) is from the same publisher ($($dependency.publisher)) as the main app ($($appJson.publisher)), using version range [$($dependency.version),$($versionParts[0])$($versionParts[1]).0.0.0)."
    return "[$($dependency.version),$($versionParts[0])$($versionParts[1]).0.0.0)"
}