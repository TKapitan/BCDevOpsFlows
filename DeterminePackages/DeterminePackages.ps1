Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Common\Import-Common.ps1" -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath "DeterminePackages.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

try {
    if ([string]::IsNullOrEmpty($ENV:AL_RUNWITH)) {
        throw "You must specify runWith in setting file or use default value."
    }

    Write-Host "Identifying what engine to use for packages: " $ENV:AL_RUNWITH
    $runWith = ($ENV:AL_RUNWITH).ToLowerInvariant()

    # Update settings from app configuration
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
    $appJsonContentApp = Get-AppJson -settings $settings
    $settings = Update-CustomCodeCops -settings $settings -runWith $runWith
    $settings = Get-DependenciesFromNuGet -settings $settings -appJsonContent $appJsonContentApp
    $settings = Get-PreviousReleaseFromNuGet -settings $settings

    # Set output variables
    $ENV:AL_SETTINGS = $($settings | ConvertTo-Json -Depth 99 -Compress)
    Write-Host "##vso[task.setvariable variable=AL_SETTINGS;]$($settings | ConvertTo-Json -Depth 99 -Compress)"
    OutputDebug -Message "Set environment variable AL_SETTINGS to ($ENV:AL_SETTINGS)"

    # Determine packages
    . (Join-Path -Path $PSScriptRoot -ChildPath "ForNuGet\DetermineNugetPackages.ps1" -Resolve) -appJsonContent $appJsonContentApp

    if ($runWith -eq 'nuget') {
        Write-Host "Using NuGet"
        # No special steps needed
    }
    elseif ($runWith -eq 'bccontainerhelper') {
        Write-Host "Using BCContainerHelper"
    
        # Tests are supported only in BCC, find test app dependencies
        $testAppFilePath = "$ENV:PIPELINE_WORKSPACE\App\Test\app.json"
        if (!(Test-Path $testAppFilePath)) {
            Write-Host "Test app.json not found for Test app at $testAppFilePath. Skipping test app package determination."
        }
        else {
            $appJsonContentTest = Get-Content $testAppFilePath -Encoding UTF8 | ConvertFrom-Json
            . (Join-Path -Path $PSScriptRoot -ChildPath "ForNuGet\DetermineNugetPackages.ps1" -Resolve) -appJsonContent $appJsonContentTest -mainAppId $appJsonContentApp.id -isTestApp
        }
        # Find BCC artifact
        . (Join-Path -Path $PSScriptRoot -ChildPath "ForBCContainerHelper\DetermineArtifactUrl.ps1" -Resolve)
    }
    else {
        throw "Unknown AL_RUNWITH value: $ENV:AL_RUNWITH. Supported values are 'NuGet' and 'BCContainerHelper'."
    }

    if ([string]::IsNullOrEmpty($ENV:AL_ARTIFACT)) {
        throw "AL_ARTIFACT is empty. Make sure you have 'artifact' set in your settings file."
    }
}
catch {
    Write-Host "##vso[task.logissue type=error]$($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($_.PSMessageDetails) {
        Write-Host $_.PSMessageDetails
    }
    Write-Host "##vso[task.complete result=Failed]"
    exit 0
}
