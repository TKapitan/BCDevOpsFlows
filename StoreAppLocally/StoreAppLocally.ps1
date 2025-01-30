Param(
    [Parameter(HelpMessage = "Specifies the minimal BC version the app supports. Must be format X.Y.Z.W", Mandatory = $true)]
    [version] $minBcVersion,
    [Parameter(HelpMessage = "Specifies whether the app is in preview only.", Mandatory = $false)]
    [string] $isPreview
)

. (Join-Path -Path $PSScriptRoot -ChildPath "StoreAppLocally.Helper.ps1" -Resolve)

$settings = $ENV:SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
foreach ($folderTypeNumber in 1..2) {
    $appFolder = $folderTypeNumber -eq 1
    $testFolder = $folderTypeNumber -eq 2
    Write-Host "Reading apps #$folderTypeNumber"
    
    if ($appFolder) {
        $folders = @($settings.appFolders)
    }
    elseif ($testFolder) {
        $folders = @($settings.testFolders)
    }
    
    Write-Host "Saving apps in following folders: $folders"
    foreach ($folderName in $folders) {
        $appJsonFilePath = Join-Path -Path $folderName -ChildPath "app.json"
        Write-Host "Saving '$appJsonFilePath' app in to shared local folder ($($settings.appArtifactSharedFolder))"
        Save-AppLocally -appArtifactSharedFolder $settings.appArtifactSharedFolder -appJsonFilePath $appJsonFilePath -minBcVersion $minBcVersion -isPreview $isPreview
    }
}
