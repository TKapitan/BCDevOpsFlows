Param(
    [Parameter(HelpMessage = "Build mode", Mandatory = $false)]
    [string] $buildMode = "Default",
    [Parameter(HelpMessage = "Specifies which properties to get from the settings file, default is all", Mandatory = $false)]
    [string] $get = ""
)
. (Join-Path -Path $PSScriptRoot -ChildPath "ReadSettings.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Output.Helper.ps1" -Resolve)

# Find requested settings
$settings = ReadSettings -buildMode $buildMode -projectSettings $ENV:AL_PROJECTSETTINGS
if ($get) {
    $getSettings = $get.Split(',').Trim()
}
else {
    $getSettings = @()
}

# Determine versioning strategy
if ($ENV:BUILD_REASON -in @("PullRequest")) {
    $settings.doNotSignApps = $true
    $settings.versioningStrategy = 15
}
if ($settings.appBuild -eq [int32]::MaxValue) {
    $settings.versioningStrategy = 15
}
if ($settings.versioningStrategy -ne -1) {
    switch ($settings.versioningStrategy -band 15) {
        0 {
            # Use BUILD_NUMBER and SYSTEM_JOBATTEMPT
            $settings.appBuild = $settings.runNumberOffset + [Int32]($ENV:BUILD_BUILDNUMBER)
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
            $settings.appRevision = $settings.runNumberOffset + [Int32]($ENV:BUILD_BUILDNUMBER)
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
            OutputMessageError -Message "Unknown version strategy $versionStrategy"
            exit
        }
    }
}
OutputMessage "AppBuild: $($settings.appBuild); AppRevision: $($settings.appRevision)"

# Set output variables
$outSettings = @{}
$settings.Keys | ForEach-Object {
    $setting = $_
    $settingValue = $settings."$setting"
    if ($settingValue -is [String] -and ($settingValue.contains("`n") -or $settingValue.contains("`r"))) {
        OutputError "Setting $setting contains line breaks, which is not supported"
    }
    $outSettings += @{ "$setting" = $settingValue }
    if ($getSettings -contains $setting) {
        if ($settingValue -is [System.Collections.Specialized.OrderedDictionary] -or $settingValue -is [hashtable]) {
            OutputMessage "##vso[task.setvariable variable=$setting;]$(ConvertTo-Json $settingValue -Depth 99 -Compress)"
        }
        else {
            OutputMessage "##vso[task.setvariable variable=$setting;]$settingValue"
        }
    }
}

$ENV:AL_SETTINGS = $($outSettings | ConvertTo-Json -Depth 99 -Compress)
OutputMessage "##vso[task.setvariable variable=AL_SETTINGS;]$($outSettings | ConvertTo-Json -Depth 99 -Compress)"
OutputMessage "Set environment variable AL_SETTINGS to ($ENV:AL_SETTINGS)"
