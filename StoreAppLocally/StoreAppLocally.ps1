Param(
    [Parameter(HelpMessage = "Specifies whether the app is in preview only.", Mandatory = $false)]
    [switch] $isPreview
)

. (Join-Path -Path $PSScriptRoot -ChildPath "StoreAppLocally.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\FindDependencies.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

$settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable
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
        $appJsonFilePath = Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath "$folderName\app.json"
        Write-Host "Saving '$appJsonFilePath' app in to shared local folder ($($settings.appArtifactSharedFolder))"

        # Find app.json & target path
        $appFile = Get-AppJsonFile -sourceAppJsonFilePath $appJsonFilePath
        $appTargetFilePathForNewAppParam = @{}
        if ($isPreview -eq $true) {
            $appTargetFilePathForNewAppParam = @{ "isPreview" = $true }
        }
        $targetPath = Get-AppTargetFilePathForNewApp -appArtifactSharedFolder $settings.appArtifactSharedFolder -appFile $appFile @appTargetFilePathForNewAppParam

        # Copy application file & app.json file to our shared folder
        $newAppFileLocation = $targetPath + (Get-AppFileName -publisher $appFile.publisher -name $appFile.name -version $appFile.version);
        New-Item -ItemType File -Path $newAppFileLocation -Force -Verbose
        Copy-Item (Get-AppSourceFileLocation -appFile $appFile) $newAppFileLocation
        Copy-Item $appJsonFilePath ($targetPath + 'app.json')
        if ($appFolder) {
            $generatedApp = @{
                "appFile"            = $newAppFileLocation
                "appJsonFile"        = ($targetPath + 'app.json')
                "applicationVersion" = $appFile.application
            }
        }
    }
}

$generatedAppJson = $generatedApp | ConvertTo-Json -Compress
$ENV:AL_APPDETAILS = $generatedAppJson
Write-Host "##vso[task.setvariable variable=AL_APPDETAILS;]$generatedAppJson"
OutputDebug -Message "Set environment variable AL_APPDETAILS to ($ENV:AL_APPDETAILS)"

foreach ($generatedAppProperty in $generatedApp.GetEnumerator()) {
    Write-Host " - $($generatedAppProperty.Name): $($generatedAppProperty.Value)"
}
