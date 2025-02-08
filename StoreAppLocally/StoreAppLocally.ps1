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
        $appJsonContent = Get-AppJsonFile -sourceAppJsonFilePath $appJsonFilePath
        $appFilePath = Get-AppSourceFileLocation -appFile $appJsonContent

        if ($testFolder -and !(Test-Path $appFilePath)) {
            Write-Host "Cannot find '$appFilePath' application file for test app. Skipping."
        }
        else {
            Write-Host "Saving '$appJsonFilePath' app in to shared local folder ($($settings.appArtifactSharedFolder))"

            # Find app.json & target path
            $appTargetFilePathForNewAppParam = @{}
            if ($isPreview -eq $true) {
                $appTargetFilePathForNewAppParam = @{ "isPreview" = $true }
            }
            $targetPath = Get-AppTargetFilePathForNewApp -appArtifactSharedFolder $settings.appArtifactSharedFolder -appFile $appJsonContent @appTargetFilePathForNewAppParam
            $targetPathAppJsonFile = $targetPath + 'app.json'
            $targetPathAppFile = $targetPath + (Get-AppFileName -publisher $appJsonContent.publisher -name $appJsonContent.name -version $appJsonContent.version);
    
            # Copy application file & app.json file to our shared folder
            New-Item -ItemType File -Path $targetPathAppFile -Force -Verbose
            Copy-Item $appFilePath $targetPathAppFile
            Copy-Item $appJsonFilePath $targetPathAppJsonFile
            if ($appFolder) {
                $generatedApp = @{
                    "appFile"            = $targetPathAppFile
                    "appJsonFile"        = $targetPathAppJsonFile
                    "applicationVersion" = $appJsonContent.application
                }
            }
        }
    }
}

$generatedAppJson = $generatedApp | ConvertTo-Json -Compress
$ENV:AL_APPDETAILS = $generatedAppJson
Write-Host "##vso[task.setvariable variable=AL_APPDETAILS;]$generatedAppJson"
OutputDebug -Message "Set environment variable AL_APPDETAILS to ($ENV:AL_APPDETAILS)"
