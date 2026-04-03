function Get-CurrentMajorVersion {
    Param()

    $currentDate = Get-Date
    $year = $currentDate.Year
    $month = $currentDate.Month

    # Calculate major version starting from Wave 1 2023 (April) as version 22
    $baseMajor = 22 + (($year - 2023) * 2)
    if ($month -ge 10) {
        return $baseMajor + 1   # October to March - Wave 2 (second release of the year)
    }
    elseif ($month -ge 4) {
        return $baseMajor       # April to September - Wave 1 (first release of the year)
    }
    else {
        return $baseMajor - 1   # January to March - still using Wave 2 from previous year
    }
}

function Get-CurrentMinorVersion {
    Param()

    $currentDate = Get-Date
    $month = $currentDate.Month

    # Calculate minor version within the major version
    if ($month -ge 10) {
        return $month - 10  # October = 0, November = 1, December = 2
    }
    elseif ($month -ge 4) {
        return $month - 4   # April = 0, May = 1, June = 2, July = 3, August = 4, September = 5
    }
    else {
        return $month + 2   # January = 3, February = 4, March = 5 (continuing from previous wave)
    }
}