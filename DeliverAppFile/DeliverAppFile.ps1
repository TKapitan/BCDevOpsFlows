Param(
    [Parameter(HelpMessage = "Specifies whether the app is in preview only.", Mandatory = $false)]
    [switch] $isPreview
)

. (Join-Path -Path $PSScriptRoot -ChildPath "DeliverAppFile.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\NuGet.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

# Initialize trusted NuGet feeds
Initialize-BCCTrustedNuGetFeeds -fromTrustedNuGetFeeds $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL -trustMicrosoftNuGetFeeds $settings.trustMicrosoftNuGetFeeds

try {
    $generatedApp = @{}
    foreach ($folderTypeNumber in 1..2) {
        $appFolder = $folderTypeNumber -eq 1
        $testFolder = $folderTypeNumber -eq 2
        
        $versionSuffix = ''
        $deliverToType = ''
        if ($appFolder) {
            $folders = @($settings.appFolders)
            if ($isPreview -eq $true) {
                $versionSuffix = 'preview'
            }
            $deliverToType = 'Apps'
        }
        elseif ($testFolder) {
            $folders = @($settings.testFolders)
            $versionSuffix = 'tests'
            $deliverToType = 'Tests'
        }

        $deliverTo = $ENV:AL_DELIVERTO | ConvertFrom-Json | ConvertTo-HashTable -recurse
        if (-not $deliverTo.ContainsKey($deliverToType)) {
            Write-Host "Delivery settings for $deliverToType is not specified, skipping..."
        }
        else {
            $deliverToConfig = $deliverTo[$deliverToType]
            if ($deliverToConfig.type -notin @('AzureDevOps', 'NuGet')) {
                Write-Error "Invalid delivery target type '$($deliverToConfig.type)'. Must be either 'AzureDevOps' or 'NuGet'."
            }

            $trustedFeeds = $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL | ConvertFrom-Json
            $deliverToContext = $trustedFeeds | Where-Object { $_.Name -eq $deliverToConfig.NugetFeedName } | Select-Object -First 1
            if (!$deliverToContext) {
                Write-Error "NuGet feed '$($deliverToConfig.NugetFeedName)' not found in trusted feeds configuration."
            }

            foreach ($folderName in $folders) {
                Push-AppToNuGetFeed -folderName $folderName -serverUrl $deliverToContext.Url -token $deliverToContext.Token @versionSuffix
                if ($appFolder) {
                    $generatedApp = @{
                        "appFile"            = $targetPathAppFile
                        "appJsonFile"        = $targetPathAppJsonFile
                        "applicationVersion" = $appJsonContent.application
                        "githubRepository"   = $ENV:BUILD_REPOSITORY_URI
                    }
                }
            }
        }
    }

    if ($generatedApp -and $generatedApp.Count -gt 0) {
        $generatedAppJson = $generatedApp | ConvertTo-Json -Compress
        $ENV:AL_APPDETAILS = $generatedAppJson
        Write-Host "##vso[task.setvariable variable=AL_APPDETAILS;]$generatedAppJson"
        OutputDebug -Message "Set environment variable AL_APPDETAILS to ($ENV:AL_APPDETAILS)"
    }
}
catch {
    Write-Host $_.Exception -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host $_.PSMessageDetails

    Write-Error "Delivery failed. See previous lines for details."
}
