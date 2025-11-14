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
    $params = @{ 
        "Source" = "https://api.nuget.org/v3/index.json"
    }

    $folder = Join-Path "$ENV:PIPELINE_WORKSPACE/App" $settings.appFolders[0]
    $appJsonFile = Join-Path $folder "app.json"
    if (Test-Path $appJsonFile) {
        $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
        $majorVersion = [Version]::Parse($appJson.application).Major
        $params += @{ 
            "MinimumVersion" = "$($majorVersion -10).0.0.0"
            "MaximumVersion" = "$($majorVersion -10 + 1).0.0.0"
        }
    }
    else {
        throw  "No app.json file found in $folder"
    }

    OutputDebug -Message "Find-Package results:"
    $searchResultsAll = Find-Package $bcDevToolsPackageName -AllVersions @params
    $searchResultsAll | ForEach-Object {
        OutputDebug -Message "Name: $($_.Name), Version: $($_.Version)"
    }
    $bcDevToolsPackageVersion = $($searchResultsAll | Sort-Object Version -Descending | Select-Object -First 1).Version
    if ([string]::IsNullOrEmpty($bcDevToolsPackageVersion)) {
        throw "Could not determine BC Dev Tools version from NuGet search results"
    }
    Write-Host "Using $bcDevToolsPackageName version $bcDevToolsPackageVersion"

    throw "DEBUG"

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
