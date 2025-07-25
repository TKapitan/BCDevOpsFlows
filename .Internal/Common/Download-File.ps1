﻿. (Join-Path -Path $PSScriptRoot -ChildPath "..\WriteOutput.Helper.ps1" -Resolve)

<#
 .Synopsis
  Download File
 .Description
  Download a file to local computer
 .Parameter sourceUrl
  Url from which the file will get downloaded
 .Parameter destinationFile
  Destinatin for the downloaded file
 .Parameter description
  Description for the download process
 .Parameter Headers
  Specify a custom header for the request
 .Parameter dontOverwrite
  Specify dontOverwrite if you want top skip downloading if the file already exists
 .Parameter timeout
  Timeout in seconds for the download
 .Example
  Download-File -sourceUrl "https://myurl/file.zip" -destinationFile "c:\temp\file.zip" -dontOverwrite
#>
function Download-File {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $sourceUrl,
        [Parameter(Mandatory = $true)]
        [string] $destinationFile,
        [string] $description = '',
        [hashtable] $headers = @{"UserAgent" = "BcContainerHelper $bcContainerHelperVersion" },
        [switch] $dontOverwrite,
        [int]    $timeout = 100
    )

    function DownloadFileLow {
        Param(
            [string] $sourceUrl,
            [string] $destinationFile,
            [switch] $dontOverwrite,
            [switch] $useDefaultCredentials,
            [switch] $skipCertificateCheck,
            [hashtable] $headers = @{"UserAgent" = "BcContainerHelper $bcContainerHelperVersion" },
            [int] $timeout = 100
        )
    
        $handler = New-Object System.Net.Http.HttpClientHandler
        if ($skipCertificateCheck) {
            Write-Host "Disabling SSL Verification on HttpClient"
            [SslVerification]::DisableSsl($handler)
        }
        if ($useDefaultCredentials) {
            $handler.UseDefaultCredentials = $true
        }
        $httpClient = New-Object System.Net.Http.HttpClient -ArgumentList $handler
        $httpClient.Timeout = [Timespan]::FromSeconds($timeout)
        $headers.Keys | ForEach-Object {
            $httpClient.DefaultRequestHeaders.Add($_, $headers."$_")
        }
        $stream = $null
        $fileStream = $null
        if ($dontOverwrite) {
            $fileMode = [System.IO.FileMode]::CreateNew
        }
        else {
            $fileMode = [System.IO.FileMode]::Create
        }
        try {
            $stream = $httpClient.GetStreamAsync($sourceUrl).GetAwaiter().GetResult()
            $fileStream = New-Object System.IO.Filestream($destinationFile, $fileMode)
            if (-not $stream.CopyToAsync($fileStream).Wait($timeout * 1000)) {
                throw "Timeout downloading file"
            }
        }
        finally {
            if ($fileStream) {
                $fileStream.Close()
                $fileStream.Dispose()
            }
            if ($stream) {
                $stream.Dispose()
            }
        }
    }

    $replaceUrls = @{
        "https://go.microsoft.com/fwlink/?LinkID=844461"                                                                = "https://bcartifacts.azureedge.net/prerequisites/DotNetCore.1.0.4_1.1.1-WindowsHosting.exe"
        "https://download.microsoft.com/download/C/9/E/C9E8180D-4E51-40A6-A9BF-776990D8BCA9/rewrite_amd64.msi"          = "https://bcartifacts.azureedge.net/prerequisites/rewrite_2.0_rtw_x64.msi"
        "https://download.microsoft.com/download/5/5/3/553C731E-9333-40FB-ADE3-E02DC9643B31/OpenXMLSDKV25.msi"          = "https://bcartifacts.azureedge.net/prerequisites/OpenXMLSDKv25.msi"
        "https://download.microsoft.com/download/A/1/2/A129F694-233C-4C7C-860F-F73139CF2E01/ENU/x86/ReportViewer.msi"   = "https://bcartifacts.azureedge.net/prerequisites/ReportViewer.msi"
        "https://download.microsoft.com/download/1/3/0/13089488-91FC-4E22-AD68-5BE58BD5C014/ENU/x86/SQLSysClrTypes.msi" = "https://bcartifacts.azureedge.net/prerequisites/SQLSysClrTypes.msi"
        "https://download.microsoft.com/download/3/A/6/3A632674-A016-4E31-A675-94BE390EA739/ENU/x64/sqlncli.msi"        = "https://bcartifacts.azureedge.net/prerequisites/sqlncli.msi"
        "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x86.exe"           = "https://bcartifacts.azureedge.net/prerequisites/vcredist_x86.exe"
    }

    if ($replaceUrls.ContainsKey($sourceUrl)) {
        $sourceUrl = $replaceUrls[$sourceUrl]
    }

    # If DropBox URL with dl=0 - replace with dl=1 (direct download = common mistake)
    if ($sourceUrl.StartsWith("https://www.dropbox.com/", "InvariantCultureIgnoreCase") -and $sourceUrl.EndsWith("?dl=0", "InvariantCultureIgnoreCase")) {
        $sourceUrl = "$($sourceUrl.Substring(0, $sourceUrl.Length-1))1"
    }

    if (Test-Path $destinationFile -PathType Leaf) {
        if ($dontOverwrite) { 
            return
        }
        Remove-Item -Path $destinationFile -Force
    }
    $path = [System.IO.Path]::GetDirectoryName($destinationFile)
    if (!(Test-Path $path -PathType Container)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if ($description) {
        Write-Host "Downloading $description to $destinationFile"
    }
    else {
        Write-Host "Downloading $destinationFile"
    }
    if ($sourceUrl -like "https://*.sharepoint.com/*download=1*") {
        Invoke-WebRequest -UseBasicParsing -Uri $sourceUrl -OutFile $destinationFile
    }
    else {
        $waitTime = 2
        while ($true) {
            try {
                DownloadFileLow -sourceUrl $sourceUrl -destinationFile $destinationFile -dontOverwrite:$dontOverwrite -timeout $timeout -headers $headers
                break
            }
            catch {
                $waitTime += $waitTime
                if ($_.Exception.Message -like '*404*' -or $waitTime -gt 60) {
                    Write-Host "##vso[task.logissue type=error]$($_.Exception.Message)"
                    Write-Host $_.ScriptStackTrace
                    if ($_.PSMessageDetails) {
                        Write-Host $_.PSMessageDetails
                    }
                    Write-Host "##vso[task.complete result=Failed]"
                    throw ($_.Exception.Message)
                }
                Write-Host "Error downloading..., retrying in $waitTime seconds..."
                OutputDebug -Message $_
                Start-Sleep -Seconds $waitTime
            }
        }
    }
}