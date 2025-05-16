Param(
    [Parameter(HelpMessage = "Build mode", Mandatory = $false)]
    [string] $buildMode = "Default",
    [Parameter(HelpMessage = "Specifies which properties to get from the settings file, default is all", Mandatory = $false)]
    [string] $get = ""
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Common\Import-Common.ps1" -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath "ReadSettings.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

try {
    # Find requested settings
    $settings = ReadSettings -buildMode $buildMode -projectSettings $ENV:AL_PROJECTSETTINGS
    if ($get) {
        $getSettings = $get.Split(',').Trim()
    }
    else {
        $getSettings = @()
    }

    # Add default settings to publish as environment variables
    if ($getSettings -notcontains "failPublishTestsOnFailureToPublishResults") {
        $getSettings += @("failPublishTestsOnFailureToPublishResults")
    }

    # Determine versioning strategy
    if ($ENV:BUILD_REASON -in @("PullRequest")) {
        $settings.versioningStrategy = 15
    }
    if ($settings.appBuild -eq [int32]::MaxValue) {
        $settings.versioningStrategy = 15
    }
    if ($settings.versioningStrategy -ne -1) {
        switch ($settings.versioningStrategy -band 15) {
            0 {
                # Use BUILD_NUMBER and SYSTEM_JOBATTEMPT
                $settings.appBuild = $settings.buildNumberOffset + [Int32]($ENV:BUILD_BUILDNUMBER)
                $settings.appRevision = [Int32]($ENV:SYSTEM_JOBATTEMPT) - 1
            }
            2 {
                # USE DATETIME
                $settings.appBuild = [Int32]([DateTime]::UtcNow.ToString('yyyyMMdd'))
                $settings.appRevision = [Int32]([DateTime]::UtcNow.ToString('HHmmss'))
            }
            3 {
                # USE BUIlD from app.json and BUILD_NUMBER
                $settings.appBuild = -1
                $settings.appRevision = $settings.buildNumberOffset + [Int32]($ENV:BUILD_BUILDNUMBER)
            }
            10 {
                # USE both from app.json (handled later in RunPipeline)
                $settings.appBuild = $null
                $settings.appRevision = $null
            }
            15 {
                # Use maxValue
                $settings.appBuild = [Int32]::MaxValue
                $settings.appRevision = 0
            }
            default {
                OutputError -Message "Unknown version strategy $versionStrategy"
                exit
            }
        }
    }
    Write-Host "AppBuild: $($settings.appBuild); AppRevision: $($settings.appRevision)"

    # Set output variables
    $outSettings = @{}
    $settings.Keys | ForEach-Object {
        $setting = $_
        $settingValue = $settings."$setting"
        if ($settingValue -is [String] -and ($settingValue.contains("`n") -or $settingValue.contains("`r"))) {
            throw "Setting $setting contains line breaks, which is not supported"
        }
        $outSettings += @{ "$setting" = $settingValue }
        if ($getSettings -contains $setting) {
            if ($settingValue -is [System.Collections.Specialized.OrderedDictionary] -or $settingValue -is [hashtable]) {
                Write-Host "##vso[task.setvariable variable=AL_$($setting.ToUpper());]$(ConvertTo-Json $settingValue -Depth 99 -Compress)"
                OutputDebug -Message "Set environment variable AL_$($setting.ToUpper()) to ($(ConvertTo-Json $settingValue -Depth 99 -Compress))"
            }
            else {
                Write-Host "##vso[task.setvariable variable=AL_$($setting.ToUpper());]$settingValue"
                OutputDebug -Message "Set environment variable AL_$($setting.ToUpper()) to ($settingValue)"
            }
        }
    }

    $ENV:AL_SETTINGS = $($outSettings | ConvertTo-Json -Depth 99 -Compress)
    Write-Host "##vso[task.setvariable variable=AL_SETTINGS;]$($outSettings | ConvertTo-Json -Depth 99 -Compress)"
    OutputDebug -Message "Set environment variable AL_SETTINGS to ($ENV:AL_SETTINGS)"
}
catch {
    Write-Host "##vso[task.logissue type=error]Error reading settings. Error message: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($_.PSMessageDetails) {
        Write-Host $_.PSMessageDetails
    }
    Write-Host "##vso[task.complete result=Failed]"
    exit 0
}