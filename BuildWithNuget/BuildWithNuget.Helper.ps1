. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

function Assert-Prerequisites {
    if (!$ENV:AL_NUGETINITIALIZED) {
        throw "Nuget not initialized - make sure that the InitNuget pipeline step is configured to run before this step."
    }
}

function Get-BuildParameters {
    param (
        $settings,
        [string]$baseRepoFolder,
        [string]$baseAppFolder,
        [string]$packageCachePath,
        [object]$appFileJson
    )

    $AppFileName = (("{0}_{1}_{2}.app" -f $appFileJson.publisher, $appFileJson.name, $appFileJson.version).Split([System.IO.Path]::GetInvalidFileNameChars()) -join '')
    $outputPath = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath ".output"

    $alcItem = Get-Item -Path (Join-Path $ENV:AL_BCDEVTOOLSFOLDER 'alc.exe')
    [System.Version]$alcVersion = $alcItem.VersionInfo.FileVersion
    $alcParameters = @(
        "/project:""$baseAppFolder""", 
        "/packagecachepath:""$packageCachePath""", 
        "/out:""$outputPath\$AppFileName""",
        "/loglevel:Warning"
    )
    if ($settings.rulesetFile) {
        $rulesetFilePath = Join-Path -Path $baseRepoFolder -ChildPath $settings.rulesetFile
        if (Test-Path -Path $rulesetFilePath) {
            OutputDebug -Message "Adding custom ruleset: $rulesetFilePath"
            $alcParameters += @("/ruleset:$rulesetFilePath")
        }
        else {
            throw "The specified ruleset file does not exist: $rulesetFilePath"
        }
    }
    # if ($EnableCodeCop -or $EnableAppSourceCop -or $EnablePerTenantExtensionCop -or $EnableUICop) {
    #     $analyzersCommonDLLPath = Join-Path $binPath 'Analyzers\Microsoft.Dynamics.Nav.Common.dll'
    #     if (Test-Path $analyzersCommonDLLPath) {
    #         $alcParameters += @("/analyzer:$(Join-Path $binPath 'Analyzers\Microsoft.Dynamics.Nav.Common.dll')")
    #     }
    # }
    if ($settings.enableCodeCop) {
        $copPath = Join-Path $ENV:AL_BCDEVTOOLSFOLDER 'Analyzers\Microsoft.Dynamics.Nav.CodeCop.dll'
        OutputDebug -Message "Enabling CodeCop, using path: $copPath"
        if (-not (Test-Path $copPath)) {
            throw "The specified CodeCop analyzer does not exist: $copPath"
        }
        $alcParameters += @("/analyzer:$copPath")
    }
    if ($settings.enableAppSourceCop) {
        $copPath = Join-Path $ENV:AL_BCDEVTOOLSFOLDER 'Analyzers\Microsoft.Dynamics.Nav.AppSourceCop.dll'
        OutputDebug -Message "Enabling AppSourceCop, using path: $copPath"
        if (-not (Test-Path $copPath)) {
            throw "The specified AppSourceCop analyzer does not exist: $copPath"
        }
        $alcParameters += @("/analyzer:$copPath")
    }
    if ($settings.enablePerTenantExtensionCop) {
        $copPath = Join-Path $ENV:AL_BCDEVTOOLSFOLDER 'Analyzers\Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll'
        OutputDebug -Message "Enabling PerTenantExtensionCop, using path: $copPath"
        if (-not (Test-Path $copPath)) {
            throw "The specified PerTenantExtensionCop analyzer does not exist: $copPath"
        }
        $alcParameters += @("/analyzer:$copPath")
    }
    if ($settings.enableUICop) {
        $copPath = Join-Path $ENV:AL_BCDEVTOOLSFOLDER 'Analyzers\Microsoft.Dynamics.Nav.UICop.dll'
        OutputDebug -Message "Enabling UICop, using path: $copPath"
        if (-not (Test-Path $copPath)) {
            throw "The specified UICop analyzer does not exist: $copPath"
        }
        $alcParameters += @("/analyzer:$copPath")
    }
    if ($settings.enableExternalRulesets) {
        OutputDebug -Message "Enabling external rulesets"
        $alcParameters += @("/enableexternalrulesets")
    }
    if ($alcVersion -ge [System.Version]"12.0.12.41479") {
        $alcParameters += @(
            "/sourceRepositoryUrl:""$ENV:BUILD_REPOSITORY_URI""",
            "/sourceCommit:""$ENV:BUILD_SOURCEVERSION""",
            "/buildBy:""BCDevOpsFlows""",
            "/buildUrl:""$ENV:BUILD_BUILDURI"""
        )
        OutputDebug -Message "Adding source code parameters:"
        OutputDebug -Message "  sourceRepositoryUrl: $ENV:BUILD_REPOSITORY_URI"
        OutputDebug -Message "  sourceCommit: $ENV:BUILD_SOURCEVERSION"
        OutputDebug -Message "  buildBy: BCDevOpsFlows"
        OutputDebug -Message "  buildUrl: $ENV:BUILD_BUILDURI"
    }
    if ($settings.ContainsKey('preprocessorSymbols')) {
        OutputDebug -Message "Adding Preprocessor symbols : $($settings.preprocessorSymbols -join ',')"
        $settings.preprocessorSymbols | where-Object { $_ } | ForEach-Object { $alcParameters += @("/D:$_") }
    }
    return $alcParameters
}

function Invoke-AlCompiler {
    param(
        [array]$Parameters
    )

    Write-Host "Using parameters:"
    $Parameters | ForEach-Object { Write-Host "  $_" }

    Push-Location
    try {
        Write-Host ".\alc.exe $([string]::Join(' ', $Parameters))"
        Set-Location $ENV:AL_BCDEVTOOLSFOLDER
        & .\alc.exe $Parameters
    }
    finally {
        Pop-Location
    }
}