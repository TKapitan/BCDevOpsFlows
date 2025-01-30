. (Join-Path -Path $PSScriptRoot -ChildPath "..\FindDependencies\FindDependencies.Helper.ps1" -Resolve)

function Get-AppDependencies {
    Param (
        [string]$appArtifactSharedFolder,
        $appJsonFilePath,
        $excludeExtensionID = $null,
        [version] $minBcVersion,
        [switch] $includeAppsInPreview
    )
    Process {
        . (Join-Path -Path $PSScriptRoot -ChildPath "FindDependencies.Helper.ps1" -Resolve)

        Write-Host "Identifying App dependencies..."
        
        if (!$appJsonFilePath) {
            Write-Host "Skipping App dependencies as the source path is not defined..."
        }
        else {
            # Find app.json 
            Write-Host "Looking for " $appJsonFilePath;
            $appFileContent = Get-AppJsonFile -sourceAppJsonFilePath $appJsonFilePath
            
            # Get all dependencies for specific extension
            $allBCDependenciesParam = @{}
            if ($includeAppsInPreview -eq $true) {
                $allBCDependenciesParam = @{ "includeAppsInPreview" = $true }
            }
            $dependencies = $(Get-AllBCDependencies -appArtifactSharedFolder $appArtifactSharedFolder -appFile $appFileContent -excludeExtensionID $excludeExtensionID -minBcVersion $minBcVersion @$allBCDependenciesParam)
            Write-Host "App dependencies: $dependencies"

            return $dependencies
        }
    }
}
