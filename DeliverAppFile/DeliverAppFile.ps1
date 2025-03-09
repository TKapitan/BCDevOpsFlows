Param(
    [Parameter(HelpMessage = "Specifies whether the app is in preview only.", Mandatory = $false)]
    [switch] $isPreview
)

. (Join-Path -Path $PSScriptRoot -ChildPath "DeliverAppFile.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

try {
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
    if ([string]::IsNullOrEmpty($settings.deliveryTarget)) {
        Write-Host "deliveryTarget setting is not specified. Skipping delivery of app files."
        exit
    }
    $deliverTo = $ENV:AL_DELIVERTO | ConvertFrom-Json | ConvertTo-HashTable -recurse
    if (-not $deliverTo.ContainsKey($settings.deliveryTarget)) {
        Write-Error "Delivery target '$($settings.deliveryTarget)' not found in delivery configuration."
    }
    $deliverToConfig = $deliverTo[$settings.deliveryTarget]
    if ($deliverToConfig.type -notin @('AzureDevOps', 'NuGet')) {
        Write-Error "Invalid delivery target type '$($deliverToConfig.type)'. Must be either 'AzureDevOps' or 'NuGet'."
    }
    $authContexts = $ENV:AL_AUTHCONTEXTS_INTERNAL | ConvertFrom-Json
    $contextVariableName = $deliverToConfig.contextVariableName
    if (!$authContexts."$contextVariableName") {
        Write-Error "Auth context '$contextVariableName' not found in auth configuration."
    }
    $deliverToContext = $authContexts[$contextVariableName]

    $isPreviewParam = @{}
    if ($isPreview -eq $true) {
        $isPreviewParam = @{ "isPreview" = $true }
    }
    
    $generatedApp = @{}
    foreach ($folderTypeNumber in 1..2) {
        $appFolder = $folderTypeNumber -eq 1
        $testFolder = $folderTypeNumber -eq 2
        if ($appFolder) {
            $folders = @($settings.appFolders)
        }
        elseif ($testFolder) {
            $folders = @($settings.testFolders)
        }

        foreach ($folderName in $folders) {
            Push-AppToNuGetFeed -folderName $folderName -serverUrl $deliverToContext.serverUrl -accessToken $deliverToContext.PATToken -isPreview:$isPreviewParam.isPreview

            if ($appFolder) {
                $generatedApp = @{
                    "appFile"            = $targetPathAppFile
                    "appJsonFile"        = $targetPathAppJsonFile
                    "applicationVersion" = $appJsonContent.application
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
