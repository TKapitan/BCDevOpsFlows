. (Join-Path -Path $PSScriptRoot -ChildPath "..\Build.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Convert-ALCOutputToAzureDevOps.Helper.ps1" -Resolve)

function Get-BuildParameters {
    param (
        $settings,
        [string]$baseRepoFolder,
        [string]$baseAppFolder,
        [string]$packageCachePath,
        [object]$appJsonContent
    )

    $AppFileName = (("{0}_{1}_{2}.app" -f $appJsonContent.publisher, $appJsonContent.name, $appJsonContent.version).Split([System.IO.Path]::GetInvalidFileNameChars()) -join '')
    $outputPath = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath ".output"

    $alcItem = Get-Item -Path (Join-Path $ENV:AL_BCDEVTOOLSFOLDER 'alc.exe')
    [System.Version]$alcVersion = $alcItem.VersionInfo.FileVersion
    OutputDebug -Message "AL Compiler version: $alcVersion"
    $alcParameters = @(
        "/project:""$baseAppFolder""", 
        "/packagecachepath:""$packageCachePath""", 
        "/out:""$outputPath\$AppFileName""",
        "/loglevel:Warning"
    )
    if ($settings.rulesetFile -is [string] -and -not [string]::IsNullOrWhiteSpace($settings.rulesetFile)) {
        $rulesetFilePath = Join-Path -Path $baseRepoFolder -ChildPath $settings.rulesetFile
        if (Test-Path -Path $rulesetFilePath) {
            OutputDebug -Message "Adding custom ruleset: $rulesetFilePath"
            $alcParameters += @("/ruleset:$rulesetFilePath")
        }
        else {
            throw "The specified ruleset file does not exist: $rulesetFilePath. Please verify that the 'rulesetFile' setting in your configuration is correct and confirm that the file exists at the specified location."
        }
    }

    $analyzers = @(
        @{ Name = "CodeCop"; Setting = "enableCodeCop"; FileName = "Microsoft.Dynamics.Nav.CodeCop.dll" },
        @{ Name = "AppSourceCop"; Setting = "enableAppSourceCop"; FileName = "Microsoft.Dynamics.Nav.AppSourceCop.dll" },
        @{ Name = "PerTenantExtensionCop"; Setting = "enablePerTenantExtensionCop"; FileName = "Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll" },
        @{ Name = "UICop"; Setting = "enableUICop"; FileName = "Microsoft.Dynamics.Nav.UICop.dll" }
    )
    $anyAnalyzerEnabled = $analyzers | Where-Object { $settings.$($_.Setting) } | Select-Object -First 1
    if ($anyAnalyzerEnabled) {
        $analyzersCommonDLLPath = 'Microsoft.Dynamics.Nav.Analyzers.Common.dll'
        $copPath = Join-Path $ENV:AL_BCDEVTOOLSFOLDER $analyzersCommonDLLPath
        if (Test-Path $copPath) {
            $alcParameters += @("/analyzer:$copPath")
        }
        elseif ($alcVersion -ge [System.Version]"15.0.0.0") {
            throw "The specified Common analyzer does not exist: $copPath"
        }
    }
    foreach ($analyzer in $analyzers) {
        if ($settings.$($analyzer.Setting)) {
            $copPath = Join-Path $ENV:AL_BCDEVTOOLSFOLDER $analyzer.FileName
            OutputDebug -Message "Enabling $($analyzer.Name), using path: $copPath"
            if (-not (Test-Path $copPath)) {
                throw "The specified $($analyzer.Name) analyzer does not exist: $copPath"
            }
            $alcParameters += @("/analyzer:$copPath")
        }
    }
    $CustomCodeCops = @()
    if ($settings.ContainsKey('customCodeCops')) {
        $CustomCodeCops = $settings.customCodeCops
    }
    if ($CustomCodeCops.Count -gt 0) {
        $CustomCodeCops | ForEach-Object {
            $copPath = $_
            if ($_ -like 'https://*') {
                $copPath = Join-Path $ENV:AL_BCDEVTOOLSFOLDER $(Split-Path $_ -Leaf)
                Download-File -SourceUrl $_ -destinationFile $copPath
            }
            $alcParameters += @("/analyzer:$copPath")
        }
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
    $existingSymbols = Get-PreprocessorSymbols -settings $settings -appJsonContent $appJsonContent
    $existingSymbols.Keys | ForEach-Object { $alcParameters += @("/D:$_") }
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
        $result = & .\alc.exe $Parameters
    }
    finally {
        Pop-Location
    }
    return $result
}

function Write-ALCOutput {
    param(
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        $alcOutput,
        [Parameter(Position = 1)]
        [ValidateSet('none', 'error', 'warning')]
        [string] $failOn,
        [scriptblock] $outputTo = { Param($line) Write-Host $line }
    )

    $Parameters = @{
        "FailOn"           = $failOn
        "AlcOutput"        = $alcOutput
        "DoNotWriteToHost" = $true
    }
    $devOpsResult = Convert-ALCOutputToAzureDevOps @Parameters
    $devOpsResult | ForEach-Object { $outputTo.Invoke($_) }
    $alcOutput | Where-Object { $_ -like "App generation failed*" } | ForEach-Object { throw $_ }
}