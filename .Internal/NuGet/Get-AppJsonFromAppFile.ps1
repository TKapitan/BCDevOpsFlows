<# 
 .Synopsis
  Extract the app.json file from an app (also from runtime packages)
 .Description
 .Parameter AppFile
  Path of the application file from which to extract the app.json
 .Example
  Get-AppJsonFromAppFile -appFile c:\temp\baseapp.app
#>
function Get-AppJsonFromAppFile {
    Param(
        [Parameter(Mandatory=$true)]
        [string] $appFile
    )

    function RunAlTool {
        Param(
            [string[]] $arguments,
            [switch] $usePrereleaseAlTool = ($bccontainerHelperConfig.usePrereleaseAlTool)
        )
        $path = DownloadLatestAlLanguageExtension -allowPrerelease:$usePrereleaseAlTool
        if ($isLinux) {
            $command = Join-Path $path 'extension/bin/linux/altool'
            if (Test-Path $command) {
                & /usr/bin/env sudo pwsh -command "& chmod +x $command"
            }
            else {
                Write-Host "No altool executable found. Using dotnet to run altool.dll."
                $command = 'dotnet'
                $arguments = @(Join-Path $path 'extension/bin/linux/altool.dll') + $arguments
            }
        } 
        elseif ($isMacOS) {
            $command = Join-Path $path 'extension/bin/darwin/altool'
            if (Test-Path $command) {
                & chmod +x $command
            }
            else {
                Write-Host "No altool executable found. Using dotnet to run altool.dll."
                $command = 'dotnet'
                $arguments = @(Join-Path $path 'extension/bin/darwin/altool.dll') + $arguments
            }
        }
        else {
            $command = Join-Path $path 'extension/bin/win32/altool.exe'
        }
        CmdDo -Command $command -arguments $arguments -returnValue -silent
    }

    $AlLanguageExtenssionPath = @('','')
    function DownloadLatestAlLanguageExtension {
        Param(
            [switch] $allowPrerelease
        )
    
        # Check if we already have the latest version downloaded and located in this session
        if ($script:AlLanguageExtenssionPath[$allowPrerelease.IsPresent]) {
            $path = $script:AlLanguageExtenssionPath[$allowPrerelease.IsPresent]
            if (Test-Path $path -PathType Container) {
                return $path
            }
            else {
                $script:AlLanguageExtenssionPath[$allowPrerelease.IsPresent] = ''
            }
        }
        
        $mutexName = "DownloadAlLanguageExtension"
        $mutex = New-Object System.Threading.Mutex($false, $mutexName)
        try {
            try {
                if (!$mutex.WaitOne(1000)) {
                    Write-Host "Waiting for other process downloading AL Language Extension"
                    $mutex.WaitOne() | Out-Null
                    Write-Host "Other process completed downloading"
                }
            }
            catch [System.Threading.AbandonedMutexException] {
               Write-Host "Other process terminated abnormally"
            }
    
            $version, $url = GetLatestAlLanguageExtensionVersionAndUrl -allowPrerelease:$allowPrerelease
            $path = Join-Path $bcContainerHelperConfig.hostHelperFolder "alLanguageExtension/$version"
            if (!(Test-Path $path -PathType Container)) {
                $AlLanguageExtensionsFolder = Join-Path $bcContainerHelperConfig.hostHelperFolder "alLanguageExtension"
                if (!(Test-Path $AlLanguageExtensionsFolder -PathType Container)) {
                    New-Item -Path $AlLanguageExtensionsFolder -ItemType Directory | Out-Null
                }
                $description = "AL Language Extension"
                if ($allowPrerelease) {
                    $description += " (Prerelease)"
                }
                $zipFile = "$path.zip"
                Download-File -sourceUrl $url -destinationFile $zipFile -Description $description
                Expand-7zipArchive -Path $zipFile -DestinationPath $path
                Remove-Item -Path $zipFile -Force
            }
            $script:AlLanguageExtenssionPath[$allowPrerelease.IsPresent] = $path
            return $path
        }
        finally {
            $mutex.ReleaseMutex()
        }
    }

    function GetLatestAlLanguageExtensionVersionAndUrl {
        Param(
            [switch] $allowPrerelease
        )
    
        $listing = Invoke-WebRequest -Method POST -UseBasicParsing `
                          -Uri https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery?api-version=3.0-preview.1 `
                          -Body '{"filters":[{"criteria":[{"filterType":8,"value":"Microsoft.VisualStudio.Code"},{"filterType":12,"value":"4096"},{"filterType":7,"value":"ms-dynamics-smb.al"}],"pageNumber":1,"pageSize":50,"sortBy":0,"sortOrder":0}],"assetTypes":[],"flags":0x192}' `
                          -ContentType application/json | ConvertFrom-Json
        
        $result =  $listing.results | Select-Object -First 1 -ExpandProperty extensions `
                             | Select-Object -ExpandProperty versions `
                             | Where-Object { ($allowPrerelease.IsPresent -or !(($_.properties.Key -eq 'Microsoft.VisualStudio.Code.PreRelease') -and ($_.properties | where-object { $_.Key -eq 'Microsoft.VisualStudio.Code.PreRelease' }).value -eq "true")) } `
                             | Select-Object -First 1
    
        if ($result) {
            $vsixUrl = $result.files | Where-Object { $_.assetType -eq "Microsoft.VisualStudio.Services.VSIXPackage"} | Select-Object -ExpandProperty source
            if ($vsixUrl) {
                return $result.version, $vsixUrl
            }
        }
        throw "Unable to locate latest AL Language Extension from the VS Code Marketplace"
    }

    $appJson = RunAlTool -arguments @('GetPackageManifest', """$appFile""") | ConvertFrom-Json
    if (!($appJson.PSObject.Properties.Name -eq "description")) { Add-Member -InputObject $appJson -MemberType NoteProperty -Name "description" -Value "" }
    if (!($appJson.PSObject.Properties.Name -eq "dependencies")) { Add-Member -InputObject $appJson -MemberType NoteProperty -Name "dependencies" -Value @() }
    return $appJson
}