Param(
    [Parameter(HelpMessage = "Specifies whether the app is in preview only.", Mandatory = $false)]
    [switch] $isPreview
)
$PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::PlainText;

. (Join-Path -Path $PSScriptRoot -ChildPath "DeliverAppFile.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\NuGet.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

$settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable

try {
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
                throw "Invalid delivery target type '$($deliverToConfig.type)'. Must be either 'AzureDevOps' or 'NuGet'."
            }

            $trustedFeeds = $ENV:AL_TRUSTEDNUGETFEEDS_INTERNAL | ConvertFrom-Json
            $deliverToContext = $trustedFeeds | Where-Object { $_.Name -eq $deliverToConfig.NugetFeedName } | Select-Object -First 1
            if (!$deliverToContext) {
                throw "NuGet feed '$($deliverToConfig.NugetFeedName)' not found in trusted feeds configuration."
            }

            foreach ($folderName in $folders) {
                Push-AppToNuGetFeed -folderName $folderName -url $deliverToContext.Url -token $deliverToContext.Token -versionSuffix $versionSuffix
            }
        }
    }
}
catch {
    Write-Host $_.Exception -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host $_.PSMessageDetails

    throw "Delivery failed. See previous lines for details."
}
