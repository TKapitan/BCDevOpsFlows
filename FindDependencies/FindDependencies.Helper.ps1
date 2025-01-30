function Get-AppJsonFile {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string] $sourceAppJsonFilePath
    ) 

    ## Find app.json
    $appFile = '';
    $PSDefaultParameterValues['*:Encoding'] = 'utf8'
    foreach ($appFilePath in $sourceAppJsonFilePath) {
        if (Test-Path -Path $appFilePath -PathType Leaf) {
            Write-Host "Trying to load json file:" $appFilePath
            $appFile = (Get-Content $appFilePath | ConvertFrom-Json);
            break;
        }
    }
    if ($appFile -eq '') {
        Write-Error "App.json file was not found for $($sourceAppJsonFilePath).";
    }
    else {
        Write-Host "App.json found for $($appFilePath)"
    }
    return $appFile;
}
function Get-BCDependencies {
    [CmdletBinding()]
    Param (
        $appFile,
        [string] $appArtifactSharedFolder
    )

    ## Lookup dependencies
    $dependencies = $appFile.dependencies;
    if ($dependencies) {
        $listOfDependencies = '';
        foreach ($dependency in $dependencies) {
            if ($listOfDependencies -ne '') {
                $listOfDependencies += ',';
            }
            $listOfDependencies += $appArtifactSharedFolder + $dependency.id + '_' + $dependency.version + '.app';        
        }
    }
    Write-Host "List of dependencies = $listOfDependencies"
}
function Get-AppSourceFileLocation {
    [CmdletBinding()]
    Param (
        $appFile
    )

    return (Join-Path -Path $ENV:BUILD_REPOSITORY_LOCALPATH -ChildPath ".output") + '/' + (Get-AppFileName -publisher $appFile.publisher -name $appFile.name -version $appFile.version);
}
function Get-AppFileName {
    [CmdletBinding()]
    Param (
        [string]$publisher,
        [string]$name,
        [string]$version
    )

    return $publisher + '_' + $name + '_' + $version + '.app';
}
function Get-AppTargetFilePath {
    [CmdletBinding()]
    Param (
        [string] $appArtifactSharedFolder,
        [string] $extensionID,
        [string] $extensionVersion,
        [switch] $includeAppsInPreview,
        [version] $minBcVersion,
        [string] $findExisting = $true
    )

    $releaseTypeFolderParam = @{}
    if ($skipAppsInPreview -eq $true) {
        [version]$latestPreviewVersion = Get-LatestVersion -appArtifactSharedFolder $appArtifactSharedFolder -extensionID $extensionID -minBcVersion $minBcVersion -releaseType 'preview'
        [version]$latestPublicVersion = Get-LatestVersion -appArtifactSharedFolder $appArtifactSharedFolder -extensionID $extensionID -minBcVersion $minBcVersion -releaseType 'public'
        $latestExistingVersion = $latestPublicVersion
        if ($latestPreviewVersion -gt $latestPublicVersion) {
            $skipAppsInPreview = $false
            $latestExistingVersion = $latestPreviewVersion
            $releaseTypeFolderParam = @{ "isPreview" = $true }
        }
    }
    $releaseTypeFolder = Get-ReleaseTypeFolderName @releaseTypeFolderParam

    if ($findExisting -ne 'true') {
        $targetFilePath = "$appArtifactSharedFolder\apps\$releaseTypeFolder\$extensionID\$extensionVersion-BC$minBcVersion\"
        Write-Host "Using '$targetFilePath' regardless if the extension exists or not"
        return $targetFilePath
    }
        
    if (-not (Test-Path -Path ("$appArtifactSharedFolder\apps\$releaseTypeFolder\$extensionID") -PathType Container)) {
        # if no extension found found, use the previous file structure, throw error if not found in that function
        return Get-AppTargetFilePathWithoutReleaseType -appArtifactSharedFolder $appArtifactSharedFolder -extensionID $extensionID -extensionVersion $extensionVersion
    }

    if ([version]$latestExistingVersion -lt [version]$extensionVersion) {
        Write-Error "Cannot find version $extensionVersion for $extensionID. Latest existing version is $latestExistingVersion."
    }
    Write-Host "Using version $latestExistingVersion for extension $extensionID";
    return "$appArtifactSharedFolder\apps\$releaseTypeFolder\$extensionID\$latestExistingVersion\";
}
function Get-ReleaseTypeFolderName {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [switch] $isPreview
    )

    $releaseTypeFolder = 'stable'
    if ($isPreview -eq $true) {
        $releaseTypeFolder = 'preview'
    }
    return $releaseTypeFolder
}
function Get-LatestVersion {
    [CmdletBinding()]
    Param (
        [string] $appArtifactSharedFolder,
        [string] $extensionID,
        [version] $minBcVersion = '0.0.0.0',
        [string] $releaseType
    )
    
    Write-Host "Searching for latest version of $extensionID in '$releaseType' folder";
    $minVersion = '0.0.0.0';
    if (-not (Test-Path -Path ("$appArtifactSharedFolder\apps\$releaseType\$extensionID") -PathType Container)) {
        Write-Host "Can not find $appArtifactSharedFolder\apps\$releaseType\$extensionID\ folder"
        return $minVersion
    }

    Write-Host "Scanning $appArtifactSharedFolder\apps\$releaseType\$extensionID\ folder"
    $sourceDirectoryContent = Get-ChildItem ("$appArtifactSharedFolder\apps\$releaseType\$extensionID\") -Directory
    foreach ($currDir in $sourceDirectoryContent) {
        if ($currDir -contains '-BC') {
            [string]$folderAppVersion = $currDir -split '-BC' | Select-Object -First 1
            [string]$folderMinBcVersion = $currDir -split '-BC' | Select-Object -Last 1
            if ([version]$folderMinBcVersion -ge [version]$minBcVersion -and [version]$folderAppVersion -gt [version]$minVersion) {
                $minVersion = $folderAppVersion
            }
        }
        else {
            [string]$folderAppVersion = $currDir
            if ([version]$folderAppVersion -gt [version]$minVersion) {
                $minVersion = $folderAppVersion
            }
        }
    }
    Write-Host "Latest preview version of" $extensionID "is" $minVersion;
    return $minVersion;
}

# FOR LEGACY REASON ONLY ->
function Get-AppTargetFilePathWithoutReleaseType {
    [CmdletBinding()]
    Param (
        [string] $appArtifactSharedFolder,
        [string] $extensionID,
        [string] $extensionVersion
    )

    Write-Warning 'Using obsoleted Get-AppTargetFilePathWithoutReleaseType as the app was not found in the preview/public folder'

    if (-not (Test-Path -Path ($appArtifactSharedFolder + "\apps\" + $extensionID) -PathType Container)) {
        Write-Error $appArtifactSharedFolder + "\apps\" + $extensionID + " does not exists."
    }

    $latestExistingVersion = Get-LatestVersion -appArtifactSharedFolder $appArtifactSharedFolder -extensionID $extensionID -releaseType ''
    if ([version]$latestExistingVersion -lt [version]$extensionVersion) {
        Write-Error "Cannot find version $extensionVersion for $extensionID. Latest existing version is $latestExistingVersion."
    }
    Write-Host "Using version $latestExistingVersion for extension $extensionID";
    return "$appArtifactSharedFolder\apps\$extensionID\$latestExistingVersion\";
}

# FOR LEGACY REASON ONLY <-

function Get-AllBCDependencies {
    [CmdletBinding()]
    Param (
        [string] $appArtifactSharedFolder,
        [string] $excludeExtensionID = "",
        [switch] $includeAppsInPreview,
        [version] $minBcVersion,
        $appFile
    )

    $listOfDependencies = ''
    foreach ($dependency in $appFile.dependencies) {
        if ($dependency.publisher -ne 'Microsoft') {
            Write-Host "Searching for dependencies for app $($dependency.name) ($($dependency.id))"
            if ($excludeExtensionID -ne '' -and $excludeExtensionID -ne $null) {
                Write-Host "Verifying the dependency is not to be excluded ($excludeExtensionID)"
            }
            if ($dependency.id -eq $excludeExtensionID) {
                Write-Host "Skipping dependency $($dependency.name) ($($dependency.id))"
            }
            else {
                Write-Host "Path:" $appArtifactSharedFolder ", id:" $dependency.id ", name: " $dependency.name ", version:" $dependency.version
                $appsLocation = Get-AppTargetFilePath -appArtifactSharedFolder $appArtifactSharedFolder -extensionID $dependency.id -extensionVersion $dependency.version -minBcVersion $minBcVersion -includeAppsInPreview $includeAppsInPreview
                $dependencyAppContent = Get-AppJsonFile -sourceAppJsonFilePath ($appsLocation + 'app.json');
                $otherDependencies = Get-AllBCDependencies -appArtifactSharedFolder $appArtifactSharedFolder -appFile $dependencyAppContent -excludeExtensionID $excludeExtensionID -minBcVersion $minBcVersion -includeAppsInPreview $includeAppsInPreview
                
                if ($otherDependencies -ne '') {
                    if ($listOfDependencies.IndexOf($otherDependencies) -eq -1) {
                        if ($listOfDependencies -ne '') {
                            $listOfDependencies += ','
                        }
                        $listOfDependencies += $otherDependencies
                    }
                }
                $dependencyAppFileLocation = $appsLocation + (Get-AppFileName -publisher $dependencyAppContent.publisher -name $dependencyAppContent.name -version $dependencyAppContent.version);
                if ($listOfDependencies.IndexOf($dependencyAppFileLocation) -eq -1) {
                    if ($listOfDependencies -ne '') {
                        $listOfDependencies += ','
                    }
                    $listOfDependencies += ($dependencyAppFileLocation)
                }
            }
        }
    }
    return $listOfDependencies;
}