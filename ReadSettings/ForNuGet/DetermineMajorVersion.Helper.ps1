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
