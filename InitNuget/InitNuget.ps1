Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Common\Import-Common.ps1" -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Nuget.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

try {
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json
    if (!$settings) {
        throw "Settings not found - make sure that the ReadSettings pipeline step is configured to run before this step."
    }

    $bcDevToolsPackageName = "Microsoft.Dynamics.BusinessCentral.Development.Tools"
    $searchResults = Find-Package Microsoft.Dynamics.BusinessCentral.Development.Tools -AllowPrereleaseVersions -AllVersions -Source "https://api.nuget.org/v3/index.json" | Sort-Object Version -Descending | Select-Object -First 1
    $bcDevToolsPackageVersion = $searchResults.Version
    if ([string]::IsNullOrEmpty($bcDevToolsPackageVersion)) {
        throw "Could not determine BC Dev Tools version from NuGet search results"
    }

    DownloadNugetPackage -packageName $bcDevToolsPackageName -packageVersion $bcDevToolsPackageVersion

    $bcDevToolsFolder = Join-Path -Path (GetNugetPackagePath -packageName $bcDevToolsPackageName -packageVersion $bcDevToolsPackageVersion) -ChildPath "Tools\net8.0\any"
    $ENV:AL_BCDEVTOOLSFOLDER = $bcDevToolsFolder
    Write-Host "##vso[task.setvariable variable=AL_BCDEVTOOLSFOLDER;]$bcDevToolsFolder"
    OutputDebug -Message "Set environment variable AL_BCDEVTOOLSFOLDER to ($ENV:AL_BCDEVTOOLSFOLDER)"

    $ENV:AL_NUGETINITIALIZED = $true
    Write-Host "##vso[task.setvariable variable=AL_NUGETINITIALIZED;]$true"
    OutputDebug -Message "Set environment variable AL_NUGETINITIALIZED to ($ENV:AL_NUGETINITIALIZED)"
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