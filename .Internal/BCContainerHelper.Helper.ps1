. (Join-Path -Path $PSScriptRoot -ChildPath "BCDevOpsFlows.Setup.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "WriteOutput.Helper.ps1" -Resolve)

#
# Download and import the BcContainerHelper module based on repository settings
# baseFolder is the repository baseFolder
#
function DownloadAndImportBcContainerHelper([string] $baseFolder = ("$ENV:PIPELINE_WORKSPACE/App")) {
    $params = @{ "ExportTelemetryFunctions" = $true }
    $repoSettingsPath = Join-Path $baseFolder $repoSettingsFile
    if (Test-Path $repoSettingsPath) {
        $params += @{ "bcContainerHelperConfigFile" = $repoSettingsPath }
    }

    if ("$ENV:AL_BCCONTAINERHELPERPATH" -and (Test-Path -Path $ENV:AL_BCCONTAINERHELPERPATH -PathType Leaf)) {
        OutputDebug -Message "Reusing BcContainerHelper from ($ENV:AL_BCCONTAINERHELPERPATH)"
        . $ENV:AL_BCCONTAINERHELPERPATH @params
        return
    }

    $repoSettingsPath = Join-Path $baseFolder $repoSettingsFile
    $bcContainerHelperVersion = $defaultBcContainerHelperVersion # Default BcContainerHelper Version is hardcoded in BCDevOpsFlows.Setup.ps1
    if (Test-Path $repoSettingsPath) {
        # Read Repository Settings file (without applying organization variables or repository variables settings files)
        # Override default BcContainerHelper version only if new version is specifically specified in repo settings file
        $repoSettings = Get-Content $repoSettingsPath -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
        if ($repoSettings.Keys -contains "BcContainerHelperVersion") {
            $bcContainerHelperVersion = $repoSettings.BcContainerHelperVersion
            Write-Host "Using BcContainerHelper $bcContainerHelperVersion version"
            if ($bcContainerHelperVersion -like "https://*") {
                throw "Setting BcContainerHelperVersion to a URL in settings is not allowed."
            }
            if ($bcContainerHelperVersion -ne 'latest' -and $bcContainerHelperVersion -ne 'preview') {
                Write-Host "::Warning::Using a specific version of BcContainerHelper is not recommended and will lead to build failures in the future. Consider removing the setting."
            }
        }
    }

    if ($bcContainerHelperVersion -eq '') {
        $bcContainerHelperVersion = "latest"
    }

    $bcContainerHelperPath = GetBcContainerHelperPath -bcContainerHelperVersion $bcContainerHelperVersion

    Write-Host "Import from $bcContainerHelperPath"
    . $bcContainerHelperPath @params
}

#
# Get Path to BcContainerHelper module (download if necessary)
#
# If $ENV:AL_BCCONTAINERHELPERPATH is set, it will be reused (ignoring the ContainerHelperVersion)
#
# ContainerHelperVersion can be:
# - preview (or dev), which will use the preview version downloaded from bccontainerhelper blob storage
# - latest, which will use the latest version downloaded from bccontainerhelper blob storage
# - a specific version, which will use the specific version downloaded from bccontainerhelper blob storage
# - none, which will use the BcContainerHelper module installed on the build agent
# - https://... - direct download url to a zip file containing the BcContainerHelper module
#
# When using direct download url, the module will be downloaded to a temp folder and will not be cached
# When using none, the module will be located in modules and used from there
# When using preview, latest or a specific version number, the module will be downloaded to a cache folder and will be reused if the same version is requested again
# This is to avoid filling up the temp folder with multiple identical versions of BcContainerHelper
# The cache folder is C:\ProgramData\BcContainerHelper on Windows and /home/<username>/.BcContainerHelper on Linux
# A Mutex will be used to ensure multiple agents aren't fighting over the same cache folder
#
# This function will set $ENV:AL_BCCONTAINERHELPERPATH, which is the path to the BcContainerHelper.ps1 file for reuse in subsequent calls
#
function GetBcContainerHelperPath([string] $bcContainerHelperVersion) {
    if ("$ENV:AL_BCCONTAINERHELPERPATH" -and (Test-Path -Path $ENV:AL_BCCONTAINERHELPERPATH -PathType Leaf)) {
        OutputDebug -Message "Reusing BcContainerHelper from ($ENV:AL_BCCONTAINERHELPERPATH)"
        return $ENV:AL_BCCONTAINERHELPERPATH
    }

    if ($bcContainerHelperVersion -eq 'None') {
        $module = Get-Module BcContainerHelper
        if (-not $module) {
            OutputError "When setting BcContainerHelperVersion to none, you need to ensure that BcContainerHelper is installed on the build agent"
        }
        $bcContainerHelperPath = Join-Path (Split-Path $module.Path -parent) "BcContainerHelper.ps1" -Resolve
    }
    else {
        $bcContainerHelperRootFolder = 'C:\ProgramData\BcContainerHelper'
        if (!(Test-Path $bcContainerHelperRootFolder)) {
            New-Item -Path $bcContainerHelperRootFolder -ItemType Directory | Out-Null
        }

        $webclient = New-Object System.Net.WebClient
        if ($bcContainerHelperVersion -like "https://*") {
            # Use temp space for private versions
            $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            Write-Host "Downloading BcContainerHelper developer version from $bcContainerHelperVersion"
            try {
                $webclient.DownloadFile($bcContainerHelperVersion, "$tempName.zip")
            }
            catch {
                $tempName = Join-Path $bcContainerHelperRootFolder ([Guid]::NewGuid().ToString())
                $bcContainerHelperVersion = "preview"
                Write-Host "Download failed, downloading BcContainerHelper $bcContainerHelperVersion version from Blob Storage"
                $webclient.DownloadFile("https://bccontainerhelper-addgd5gzaxf9fneh.b02.azurefd.net/public/$($bcContainerHelperVersion).zip", "$tempName.zip")
            }
        }
        else {
            $tempName = Join-Path $bcContainerHelperRootFolder ([Guid]::NewGuid().ToString())
            Write-Host "Downloading BcContainerHelper $bcContainerHelperVersion version from Blob Storage"
            $webclient.DownloadFile("https://bccontainerhelper-addgd5gzaxf9fneh.b02.azurefd.net/public/$($bcContainerHelperVersion).zip", "$tempName.zip")
        }
        Expand-7zipArchive -Path "$tempName.zip" -DestinationPath $tempName
        $bcContainerHelperPath = (Get-Item -Path (Join-Path $tempName "*\BcContainerHelper.ps1")).FullName
        Remove-Item -Path "$tempName.zip" -ErrorAction SilentlyContinue
        if ($bcContainerHelperVersion -notlike "https://*") {
            # Check whether the version is already available in the cache
            $version = ([System.IO.File]::ReadAllText((Join-Path $tempName 'BcContainerHelper/Version.txt'), [System.Text.Encoding]::UTF8)).Trim()
            $cacheFolder = Join-Path $bcContainerHelperRootFolder $version
            # To avoid two agents on the same machine downloading the same version at the same time, use a mutex
            $buildMutexName = "DownloadAndImportBcContainerHelper"
            $buildMutex = New-Object System.Threading.Mutex($false, $buildMutexName)
            try {
                try {
                    if (!$buildMutex.WaitOne(1000)) {
                        Write-Host "Waiting for other process loading BcContainerHelper"
                        $buildMutex.WaitOne() | Out-Null
                        Write-Host "Other process completed loading BcContainerHelper"
                    }
                }
                catch [System.Threading.AbandonedMutexException] {
                    Write-Host "Other process terminated abnormally"
                }
                if (Test-Path $cacheFolder) {
                    Remove-Item $tempName -Recurse -Force
                }
                else {
                    Rename-Item -Path $tempName -NewName $version
                }
            }
            finally {
                $buildMutex.ReleaseMutex()
                $buildMutex.Close()
            }
            $bcContainerHelperPath = Join-Path $cacheFolder "BcContainerHelper/BcContainerHelper.ps1"
        }
    }

    $ENV:AL_BCCONTAINERHELPERPATH = $bcContainerHelperPath
    Write-Host "##vso[task.setvariable variable=AL_BCCONTAINERHELPERPATH;]$bcContainerHelperPath"
    OutputDebug -Message "Set environment variable AL_BCCONTAINERHELPERPATH to ($ENV:AL_BCCONTAINERHELPERPATH)"
    return $bcContainerHelperPath
}

function Expand-7zipArchive {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [string] $DestinationPath
    )

    $7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"

    $use7zip = $false
    if (Test-Path -Path $7zipPath -PathType Leaf) {
        try {
            $use7zip = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($7zipPath).FileMajorPart -ge 19
        }
        catch {
            $use7zip = $false
        }
    }

    if ($use7zip) {
        OutputDebug -Message "Using 7zip"
        Set-Alias -Name 7z -Value $7zipPath
        $command = '7z x "{0}" -o"{1}" -aoa -r' -f $Path, $DestinationPath
        Invoke-Expression -Command $command | Out-Null
    }
    else {
        OutputDebug -Message "Using Expand-Archive"
        Expand-Archive -Path $Path -DestinationPath "$DestinationPath" -Force
    }
}
