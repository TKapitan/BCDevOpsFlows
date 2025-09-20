Param(
    [Parameter(HelpMessage = "Specifies whether the app is in preview only.", Mandatory = $false)]
    [switch] $isPreview
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Common\Import-Common.ps1" -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath "DeliverAppFile.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\NuGet.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

try {
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
    foreach ($folderTypeNumber in 1..2) {
        $appFolder = $folderTypeNumber -eq 1
        $testFolder = $folderTypeNumber -eq 2
        
        $versionSuffix = ''
        $deliverToType = ''
        $deliverPackage = $true
        if ($appFolder) {
            $folders = @($settings.appFolders)
            if ($isPreview -eq $true) {
                $versionSuffix = 'preview'
            }
            if (-not $settings.ContainsKey('appDeliverToType') -or [string]::IsNullOrWhiteSpace($settings.appDeliverToType)) {
                Write-Host "Delivery target type is not specified, skipping..."
                $deliverPackage = $false
            }
            else {
                $deliverToType = $settings.appDeliverToType
            }
        }
        elseif ($testFolder) {
            $folders = @($settings.testFolders)
            $versionSuffix = 'tests'
            if (-not $settings.ContainsKey('testDeliverToType') -or [string]::IsNullOrWhiteSpace($settings.testDeliverToType)) {
                Write-Host "Delivery target type is not specified, skipping..."
                $deliverPackage = $false
            }
            else {
                $deliverToType = $settings.testDeliverToType
            }
        }

        $deliverTo = $ENV:AL_DELIVERTO | ConvertFrom-Json | ConvertTo-HashTable -recurse
        if (-not $deliverTo.ContainsKey($deliverToType)) {
            Write-Host "Delivery settings for $deliverToType is not specified, skipping..."
            $deliverPackage = $false
        }

        if ($deliverPackage) {
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
                $testFolder = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath $folderName
                if (Test-Path $testFolder) {
                    Push-AppToNuGetFeed -folderName $folderName -url $deliverToContext.Url -token $deliverToContext.Token -versionSuffix $versionSuffix
                }
            }
        }
    }
}
catch {
    Write-Host "##vso[task.logissue type=error]Error while delivering the app to storage. Error message: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($_.PSMessageDetails) {
        Write-Host $_.PSMessageDetails
    }
    Write-Host "##vso[task.complete result=Failed]"
    exit 0
}
