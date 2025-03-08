function Get-AppDependencies {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string] $appJsonFilePath,
        [string] $excludeExtensionID = $null,
        [Parameter(Mandatory = $true)]
        [version] $minBcVersion,
        [switch] $skipAppsInPreview
    )
    Process {
        Write-Host "Identifying App dependencies..."
        
        if (!$appJsonFilePath) {
            Write-Host "Skipping App dependencies as the source path is not defined..."
        }
        else {
            # Find app.json 
            OutputDebug -Message "Looking for  $appJsonFilePath";
            $appFileContent = Get-AppJsonFile -sourceAppJsonFilePath $appJsonFilePath
            
            # Get all dependencies for specific extension
            $allBCDependenciesParam = @{}
            if ($skipAppsInPreview -eq $true) {
                $allBCDependenciesParam = @{ "skipAppsInPreview" = $true }
            }
            $dependenciesAsHashSet = Get-AllBCDependencies -excludeExtensionID $excludeExtensionID -minBcVersion $minBcVersion -appFile $appFileContent  @allBCDependenciesParam

            $dependencies = if ($dependenciesAsHashSet -is [System.Collections.Generic.HashSet[PSCustomObject]]) {
                $dependenciesAsHashSet.ToArray()
            }
            else {
                @($dependenciesAsHashSet)
            }
            Write-Host "App dependencies: $dependencies"
            return $dependencies
        }
    }
}
function Get-LatestRelease {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string] $appId
    )

    $appFolder = Get-AppTargetFilePath -extensionID $appId -skipAppsInPreview
    $appJsonContent = Get-AppJsonFile -sourceAppJsonFilePath ($appFolder + 'app.json')
    $appFilePath = $appFolder + (Get-AppFileName -publisher $appJsonContent.publisher -name $appJsonContent.name -version $appJsonContent.version)
    return $appFilePath
}
function Get-AppJsonFile {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string] $sourceAppJsonFilePath
    ) 

    ## Find app.json
    $appFile = '';
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $encoding = 'utf8'
        $PSDefaultParameterValues['*:Encoding'] = $encoding
    }
    else {
        $encoding = 'UTF8'
        $PSDefaultParameterValues['*:Encoding'] = $encoding
    }
    foreach ($appFilePath in $sourceAppJsonFilePath) {
        if (Test-Path -Path $appFilePath -PathType Leaf) {
            OutputDebug -Message "Trying to load json file: $appFilePath"
            $appFile = (Get-Content $appFilePath -Encoding $encoding | ConvertFrom-Json);
            break;
        }
    }
    if ($appFile -eq '') {
        Write-Error "App.json file was not found for $($sourceAppJsonFilePath).";
    }
    else {
        OutputDebug -Message "App.json found for $($appFilePath)"
    }
    return $appFile;
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
        [Parameter(Mandatory = $true)]
        [string] $extensionID,
        [version] $minBcVersion = '0.0.0.0',
        [version] $extensionVersion = '0.0.0.0',
        [switch] $skipAppsInPreview
    )

    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json
    $basePath = $settings.writableFolderPath

    [version]$latestPublicVersion = Get-LatestVersion -extensionID $extensionID -minBcVersion $minBcVersion -releaseType 'public'
    $latestExistingVersion = $latestPublicVersion

    $releaseTypeFolderParam = @{}
    if ($skipAppsInPreview -eq $false) {
        [version]$latestPreviewVersion = Get-LatestVersion -extensionID $extensionID -minBcVersion $minBcVersion -releaseType 'preview'
        if ([version]::Parse($latestPreviewVersion) -gt [version]::Parse($latestPublicVersion)) {
            $latestExistingVersion = $latestPreviewVersion
            $releaseTypeFolderParam = @{ "isPreview" = $true }
        }
    }
    $releaseTypeFolder = Get-ReleaseTypeFolderName @releaseTypeFolderParam

    if (-not (Test-Path -Path ("$basePath\apps\$releaseTypeFolder\$extensionID") -PathType Container)) {
        # if no extension found found, use the previous file structure, throw error if not found in that function
        return Get-AppTargetFilePathWithoutReleaseType -extensionID $extensionID -extensionVersion $extensionVersion
    }

    if ([version]$latestExistingVersion -eq [version]'0.0.0.0') {
        Write-Error "Cannot find any version for $extensionID."
    }
    if ([version]$latestExistingVersion -lt [version]$extensionVersion) {
        Write-Error "Cannot find version $extensionVersion for $extensionID. Latest existing version is $latestExistingVersion."
    }

    OutputDebug -Message "Looking for version $latestExistingVersion for extension $extensionID for all BC versions";
    $versionFolder = Get-ChildItem ("$basePath\apps\$releaseTypeFolder\$extensionID\") -Directory | Where-Object { $_.Name.StartsWith($latestExistingVersion) } | Select-Object -First 1
    if (-not $versionFolder) {
        Write-Error "Cannot find version folder starting with $latestExistingVersion for $extensionID in $basePath\apps\$releaseTypeFolder\$extensionID\"
    }
    OutputDebug -Message "Using version $($versionFolder.Name) for extension $extensionID";
    return "$basePath\apps\$releaseTypeFolder\$extensionID\$($versionFolder.Name)\"
}
function Get-ReleaseTypeFolderName {
    [CmdletBinding()]
    Param (
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
        [string] $extensionID,
        [version] $minBcVersion = '0.0.0.0',
        [string] $releaseType
    )

    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json
    $basePath = $settings.writableFolderPath
    
    OutputDebug -Message "Searching for latest version of $extensionID in '$releaseType' folder";
    $minVersion = '0.0.0.0';
    if (-not (Test-Path -Path ("$basePath\apps\$releaseType\$extensionID") -PathType Container)) {
        Write-Host "Can not find $basePath\apps\$releaseType\$extensionID\ folder"
        return $minVersion
    }

    OutputDebug -Message "Scanning $basePath\apps\$releaseType\$extensionID\ folder"
    $sourceDirectoryContent = Get-ChildItem ("$basePath\apps\$releaseType\$extensionID\") -Directory
    foreach ($currDir in $sourceDirectoryContent) {
        if ($currDir.Name -like '*-BC*') {
            [string]$folderAppVersion = $currDir.Name -split '-BC' | Select-Object -First 1
            [string]$folderMinBcVersion = $currDir.Name -split '-BC' | Select-Object -Last 1
            if ([version]$folderMinBcVersion -ge [version]$minBcVersion -and [version]::Parse($folderAppVersion) -gt [version]::Parse($minVersion)) {
                $minVersion = $folderAppVersion
            }
        }
        else {
            [string]$folderAppVersion = $currDir.Name
            if ([version]::Parse($folderAppVersion) -gt [version]::Parse($minVersion)) {
                $minVersion = $folderAppVersion
            }
        }
    }
    OutputDebug -Message "Latest $releaseType version of $extensionID is $minVersion";
    return $minVersion;
}

# FOR LEGACY REASON ONLY ->
function Get-AppTargetFilePathWithoutReleaseType {
    [CmdletBinding()]
    Param (
        [string] $extensionID,
        [version] $extensionVersion = '0.0.0.0'
    )
    
    $settings = $ENV:AL_SETTINGS | ConvertFrom-Json
    $basePath = $settings.writableFolderPath

    Write-Warning 'Using obsoleted Get-AppTargetFilePathWithoutReleaseType as the app was not found in the preview/public folder'

    if (-not (Test-Path -Path ($basePath + "\apps\" + $extensionID) -PathType Container)) {
        Write-Error $basePath + "\apps\" + $extensionID + " does not exists."
    }

    $latestExistingVersion = Get-LatestVersion -extensionID $extensionID -releaseType ''
    if ([version]$latestExistingVersion -eq [version]'0.0.0.0') {
        Write-Error "Cannot find any version for $extensionID."
    }
    if ([version]$latestExistingVersion -lt [version]$extensionVersion) {
        Write-Error "Cannot find version $extensionVersion for $extensionID. Latest existing version is $latestExistingVersion."
    }
    Write-Host "Using version $latestExistingVersion for extension $extensionID";
    return "$basePath\apps\$extensionID\$latestExistingVersion\";
}

# FOR LEGACY REASON ONLY <-

function Get-AllBCDependencies {
    [CmdletBinding()]
    Param (
        [System.Collections.Generic.HashSet[PSCustomObject]] $dependencies = $null,
        [string] $excludeExtensionID = "",
        [switch] $skipAppsInPreview,
        [version] $minBcVersion,
        $appFile
    )

    if ($null -eq $dependencies) {
        $dependencies = [System.Collections.Generic.HashSet[PSCustomObject]]::new()
    }
    
    $appTargetFilePathParam = @{}
    $allBCDependencies = @{}
    if ($skipAppsInPreview) {
        $appTargetFilePathParam = @{ "skipAppsInPreview" = $true }
        $allBCDependencies = @{ "skipAppsInPreview" = $true }
    }

    foreach ($dependency in $appFile.dependencies) {
        if ($dependency.publisher -ne 'Microsoft' -and $dependency.id -ne $excludeExtensionID) {
            OutputDebug -Message "Processing dependency: $($dependency.name) ($($dependency.id))"
            $appsLocation = Get-AppTargetFilePath -extensionID $dependency.id -extensionVersion $dependency.version -minBcVersion $minBcVersion @appTargetFilePathParam
            $dependencyAppJsonContent = Get-AppJsonFile -sourceAppJsonFilePath ($appsLocation + 'app.json')
            
            $dependencyObject = Get-DependencyObject -dependencyFolder $appsLocation -dependencyAppJsonContent $dependencyAppJsonContent
            if (-not ($dependencies | Where-Object { $_.appFile -eq $dependencyObject.appFile })) {
                $dependencies.Add($dependencyObject)
                OutputDebug -Message "Adding dependency: $($dependencyObject.id) from $($dependencyObject.appFile)"

                # Process inner dependencies first
                $dependencies = Get-AllBCDependencies -dependencies $dependencies -excludeExtensionID $excludeExtensionID -minBcVersion $minBcVersion -appFile $dependencyAppJsonContent @allBCDependencies 
            }
            else {
                OutputDebug -Message "Dependency already exists: $($dependencyObject.id) from $($dependencyObject.appFile)"
            }
        }
    }
    return $dependencies
}

function Get-DependencyObject {
    [CmdletBinding()]
    Param (
        $dependencyFolder,
        $dependencyAppJsonContent
    )

    $newDependency = [PSCustomObject]@{
        id      = ''
        appFile = ''
    }
    $newDependency.id = $dependencyAppJsonContent.id
    $newDependency.appFile = $dependencyFolder + (Get-AppFileName -publisher $dependencyAppJsonContent.publisher -name $dependencyAppJsonContent.name -version $dependencyAppJsonContent.version)
    OutputDebug -Message "Creating app object: $($newDependency.id), $($newDependency.name) from $($newDependency.appFile)"
    return $newDependency
}