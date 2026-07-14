. (Join-Path -Path $PSScriptRoot -ChildPath "WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "CloudAuth.Helper.ps1" -Resolve)

# Container-free Business Central cloud API functions used by the deployment steps.
# These mirror the REST flows of the corresponding BcContainerHelper functions
# (Publish-PerTenantExtensionApps, Publish-BcContainerApp -useDevEndpoint,
# Get-BcEnvironmentInstalledExtensions, Install-BcAppFromAppSource) without importing the module.

function Get-BCDevOpsFlowsApiBaseUrl {
    Param()

    return "https://api.businesscentral.dynamics.com"
}

# Reads the app manifest (NavxManifest.xml) directly from a .app file and returns it in
# app.json shape. Works for regular apps and runtime packages and needs no external tools -
# .app files are a 40-byte NAVX header followed by regular zip content.
function Get-BCDevOpsFlowsAppManifest {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $appFile
    )

    Add-Type -AssemblyName System.IO.Compression | Out-Null
    $bytes = [System.IO.File]::ReadAllBytes($appFile)
    $offset = 0
    if ($bytes.Length -gt 40 -and $bytes[0] -eq 0x4E -and $bytes[1] -eq 0x41 -and $bytes[2] -eq 0x56 -and $bytes[3] -eq 0x58) {
        # 'NAVX' magic - skip the 40-byte prefix to get to the zip content
        $offset = 40
    }
    $memoryStream = [System.IO.MemoryStream]::new($bytes, $offset, $bytes.Length - $offset, $false)
    try {
        $zip = [System.IO.Compression.ZipArchive]::new($memoryStream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -eq 'NavxManifest.xml' } | Select-Object -First 1
            if (!$entry) {
                throw "NavxManifest.xml not found in $appFile"
            }
            $reader = [System.IO.StreamReader]::new($entry.Open())
            try {
                [xml]$manifest = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $zip.Dispose()
        }
    }
    finally {
        $memoryStream.Dispose()
    }

    $app = $manifest.Package.App
    $dependencies = @()
    if ($manifest.Package.Dependencies -and $manifest.Package.Dependencies.Dependency) {
        $dependencies = @($manifest.Package.Dependencies.Dependency | ForEach-Object {
                [PSCustomObject]@{
                    "id"        = "$($_.Id)"
                    "name"      = "$($_.Name)"
                    "publisher" = "$($_.Publisher)"
                    "version"   = "$($_.MinVersion)"
                }
            })
    }
    $idRanges = @()
    if ($manifest.Package.IdRanges -and $manifest.Package.IdRanges.IdRange) {
        $idRanges = @($manifest.Package.IdRanges.IdRange | ForEach-Object {
                [PSCustomObject]@{
                    "from" = [int]"$($_.MinObjectId)"
                    "to"   = [int]"$($_.MaxObjectId)"
                }
            })
    }
    return [PSCustomObject]@{
        "id"           = "$($app.Id)"
        "name"         = "$($app.Name)"
        "publisher"    = "$($app.Publisher)"
        "version"      = "$($app.Version)"
        "application"  = "$($app.Application)"
        "platform"     = "$($app.Platform)"
        "dependencies" = $dependencies
        "idRanges"     = $idRanges
    }
}

function Copy-BCDevOpsFlowsAppFilesToFolder {
    Param(
        [Parameter(Mandatory = $true)]
        $appFiles,
        [Parameter(Mandatory = $true)]
        [string] $folder
    )

    if (!(Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory | Out-Null
    }
    $result = @()
    foreach ($appFile in @($appFiles | Where-Object { $_ })) {
        if (-not (Test-Path -Path $appFile -PathType Leaf)) {
            Write-Host "::Warning::File $appFile not found, skipping"
            continue
        }
        if ($appFile -like '*.zip') {
            $tmpFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            Expand-Archive -Path $appFile -DestinationPath $tmpFolder -Force
            try {
                Get-ChildItem -Path $tmpFolder -Filter '*.app' -Recurse | ForEach-Object {
                    $destination = Join-Path $folder $_.Name
                    Copy-Item -Path $_.FullName -Destination $destination -Force
                    $result += $destination
                }
            }
            finally {
                Remove-Item -Path $tmpFolder -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            $destination = Join-Path $folder ([System.IO.Path]::GetFileName($appFile))
            Copy-Item -Path $appFile -Destination $destination -Force
            $result += $destination
        }
    }
    return $result
}

# Sorts app files so dependencies come before dependents. Apps in excludeInstalledApps
# (entries with id and version) that are already installed in the same or a newer version
# are skipped with a message, mirroring Sort-AppFilesByDependencies -excludeInstalledApps.
function Sort-BCDevOpsFlowsAppFilesByDependencies {
    Param(
        [Parameter(Mandatory = $false)]
        [string[]] $appFiles = @(),
        [Parameter(Mandatory = $false)]
        $excludeInstalledApps = @()
    )

    if (!$appFiles) {
        return @()
    }
    $apps = @()
    $files = @{}
    foreach ($appFile in $appFiles) {
        $manifest = Get-BCDevOpsFlowsAppManifest -appFile $appFile
        $key = "$($manifest.id):$($manifest.version)"
        if (-not $files.ContainsKey($key)) {
            $files[$key] = $appFile
            $apps += @($manifest)
        }
    }

    $sortedApps = [System.Collections.Generic.List[object]]::new()
    function AddAppWithDependencies {
        Param($anApp)
        $alreadyAdded = $sortedApps | Where-Object { $_.id -eq $anApp.id -and $_.version -eq $anApp.version }
        if (-not $alreadyAdded) {
            foreach ($dependency in $anApp.dependencies) {
                $dependentApp = $apps | Where-Object { $_.id -eq $dependency.id } | Select-Object -First 1
                if ($dependentApp) {
                    AddAppWithDependencies -anApp $dependentApp
                }
            }
            $sortedApps.Add($anApp)
        }
    }
    foreach ($app in $apps) {
        AddAppWithDependencies -anApp $app
    }

    $result = @()
    foreach ($app in $sortedApps) {
        $appFileName = [System.IO.Path]::GetFileName($files["$($app.id):$($app.version)"])
        $installedApp = @($excludeInstalledApps) | Where-Object { $_ -and $_.id -eq $app.id } | Select-Object -First 1
        if ($installedApp -and ([System.Version]$app.version -eq [System.Version]"$($installedApp.version)")) {
            Write-Host "$appFileName is already installed with the same version"
        }
        elseif ($installedApp -and ([System.Version]$app.version -lt [System.Version]"$($installedApp.version)")) {
            Write-Host "::Warning::$appFileName is already installed with a newer version ($($installedApp.version))"
        }
        else {
            $result += $files["$($app.id):$($app.version)"]
        }
    }
    return $result
}

# Extracts the response body from a failed REST call so API error details are not lost
function Get-BCDevOpsFlowsExtendedErrorMessage {
    Param(
        [Parameter(Mandatory = $true)]
        $errorRecord
    )

    $message = $errorRecord.Exception.Message
    try {
        if ($errorRecord.ErrorDetails -and $errorRecord.ErrorDetails.Message) {
            $errorDetails = $errorRecord.ErrorDetails.Message | ConvertFrom-Json
            if ($errorDetails.error -and $errorDetails.error.message) {
                $message += " $($errorDetails.error.message)"
            }
            elseif ($errorDetails.message) {
                $message += " $($errorDetails.message)"
            }
        }
    }
    catch {
        return $message
    }
    return $message
}

function Get-BCDevOpsFlowsInstalledExtensions {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $authContext,
        [Parameter(Mandatory = $true)]
        [string] $environment,
        [Parameter(Mandatory = $false)]
        [string] $companyName = ''
    )

    $automationApiUrl = "$((Get-BCDevOpsFlowsApiBaseUrl).TrimEnd('/'))/v2.0/$environment/api/microsoft/automation/v1.0"
    $companies = Invoke-RestMethodWithRetry -parameters @{ "Headers" = (Get-BCDevOpsFlowsAuthHeaders -authContext $authContext); "Method" = 'Get'; "Uri" = "$automationApiUrl/companies"; "UseBasicParsing" = $true }
    $company = $companies.value | Where-Object { ($companyName -eq "") -or ($_.name -eq $companyName) } | Select-Object -First 1
    if (!($company)) {
        throw "No company $companyName"
    }
    try {
        return (Invoke-RestMethodWithRetry -parameters @{ "Headers" = (Get-BCDevOpsFlowsAuthHeaders -authContext $authContext); "Method" = 'Get'; "Uri" = "$automationApiUrl/companies($($company.id))/extensions"; "UseBasicParsing" = $true }).value
    }
    catch {
        throw (Get-BCDevOpsFlowsExtendedErrorMessage -errorRecord $_)
    }
}

# Publishes and installs per-tenant extensions through the automation API,
# mirroring BcContainerHelper's Publish-PerTenantExtensionApps
function Publish-BCDevOpsFlowsPerTenantExtensionApps {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $authContext,
        [Parameter(Mandatory = $true)]
        [string] $environment,
        [Parameter(Mandatory = $true)]
        $appFiles,
        [Parameter(Mandatory = $false)]
        [string] $companyName = '',
        [ValidateSet('Add', 'Force')]
        [string] $schemaSyncMode = 'Add'
    )

    $automationApiUrl = "$((Get-BCDevOpsFlowsApiBaseUrl).TrimEnd('/'))/v2.0/$environment/api/microsoft/automation/v2.0"

    $companies = Invoke-RestMethodWithRetry -parameters @{ "Headers" = (Get-BCDevOpsFlowsAuthHeaders -authContext $authContext); "Method" = 'Get'; "Uri" = "$automationApiUrl/companies"; "UseBasicParsing" = $true }
    $company = $companies.value | Where-Object { ($companyName -eq "") -or ($_.name -eq $companyName) } | Select-Object -First 1
    if (!($company)) {
        throw "No company $companyName"
    }
    $companyId = $company.id
    Write-Host "Company '$($company.name)' has id $companyId"

    $extensions = (Invoke-RestMethodWithRetry -parameters @{ "Headers" = (Get-BCDevOpsFlowsAuthHeaders -authContext $authContext); "Method" = 'Get'; "Uri" = "$automationApiUrl/companies($companyId)/extensions"; "UseBasicParsing" = $true }).value | Sort-Object -Property displayName
    Write-Host "Extensions before:"
    $extensions | ForEach-Object { Write-Host " - $($_.DisplayName), Version $($_.versionMajor).$($_.versionMinor).$($_.versionBuild).$($_.versionRevision), Installed=$($_.isInstalled)" }

    $body = @{ "schedule" = "Current Version" }
    $appDep = $extensions | Where-Object { $_.DisplayName -eq 'Application' } | Select-Object -First 1
    $appDepVer = [System.Version]"$($appDep.versionMajor).$($appDep.versionMinor).$($appDep.versionBuild).$($appDep.versionRevision)"
    if ($appDepVer -ge [System.Version]"21.2.0.0") {
        if ($schemaSyncMode -eq 'Force') {
            $body."SchemaSyncMode" = "Force Sync"
        }
        else {
            $body."SchemaSyncMode" = "Add"
        }
    }
    elseif ($schemaSyncMode -eq 'Force') {
        throw 'SchemaSyncMode Force is not supported before version 21.2'
    }

    $ifMatchHeader = @{ "If-Match" = '*' }
    $jsonHeader = @{ "Content-Type" = 'application/json' }
    $streamHeader = @{ "Content-Type" = 'application/octet-stream' }
    try {
        foreach ($appFile in @(Sort-BCDevOpsFlowsAppFilesByDependencies -appFiles @($appFiles))) {
            Write-Host "$([System.IO.Path]::GetFileName($appFile)) - "
            $appJson = Get-BCDevOpsFlowsAppManifest -appFile $appFile
            $existingApp = $extensions | Where-Object { $_.id -eq $appJson.id -and $_.isInstalled } | Select-Object -First 1
            if ($existingApp) {
                $existingVersion = [System.Version]"$($existingApp.versionMajor).$($existingApp.versionMinor).$($existingApp.versionBuild).$($existingApp.versionRevision)"
                if ($existingVersion -ge [System.Version]$appJson.version) {
                    Write-Host "already installed"
                    continue
                }
                Write-Host "upgrading"
            }
            else {
                Write-Host "publishing and installing"
            }

            $extensionUpload = (Invoke-RestMethod -Method Get -Uri "$automationApiUrl/companies($companyId)/extensionUpload" -Headers (Get-BCDevOpsFlowsAuthHeaders -authContext $authContext) -TimeoutSec 300).value | Select-Object -First 1
            if ($extensionUpload -and $extensionUpload.systemId) {
                $extensionUpload = Invoke-RestMethod `
                    -Method Patch `
                    -Uri "$automationApiUrl/companies($companyId)/extensionUpload($($extensionUpload.systemId))" `
                    -Headers ((Get-BCDevOpsFlowsAuthHeaders -authContext $authContext) + $ifMatchHeader + $jsonHeader) `
                    -Body ($body | ConvertTo-Json -Compress) `
                    -TimeoutSec 300
            }
            else {
                $extensionUpload = Invoke-RestMethod `
                    -Method Post `
                    -Uri "$automationApiUrl/companies($companyId)/extensionUpload" `
                    -Headers ((Get-BCDevOpsFlowsAuthHeaders -authContext $authContext) + $jsonHeader) `
                    -Body ($body | ConvertTo-Json -Compress) `
                    -TimeoutSec 300
            }
            if ($null -eq $extensionUpload.systemId) {
                throw "Unable to upload extension"
            }
            $fileStream = [System.IO.File]::OpenRead($appFile)
            try {
                Invoke-RestMethod `
                    -Method Patch `
                    -Uri $extensionUpload.'extensionContent@odata.mediaEditLink' `
                    -Headers ((Get-BCDevOpsFlowsAuthHeaders -authContext $authContext) + $ifMatchHeader + $streamHeader) `
                    -Body $fileStream `
                    -TimeoutSec 600 | Out-Null
            }
            finally {
                $fileStream.Close()
            }
            Invoke-RestMethod `
                -Method Post `
                -Uri "$automationApiUrl/companies($companyId)/extensionUpload($($extensionUpload.systemId))/Microsoft.NAV.upload" `
                -Headers ((Get-BCDevOpsFlowsAuthHeaders -authContext $authContext) + $ifMatchHeader) `
                -TimeoutSec 300 `
                -ErrorAction SilentlyContinue | Out-Null

            # Poll the deployment status until the extension is installed or fails
            $completed = $false
            $errCount = 0
            $sleepSeconds = 30
            $lastStatus = ''
            while (!$completed) {
                Start-Sleep -Seconds $sleepSeconds
                try {
                    $extensionDeploymentStatuses = (Invoke-RestMethod -Headers (Get-BCDevOpsFlowsAuthHeaders -authContext $authContext) -Method Get -Uri "$automationApiUrl/companies($companyId)/extensionDeploymentStatus" -UseBasicParsing -TimeoutSec 300).value
                    $thisExtension = $extensionDeploymentStatuses | Where-Object { $_.publisher -eq $appJson.publisher -and $_.name -eq $appJson.name -and $_.appVersion -eq $appJson.version }
                    if ($null -eq $thisExtension) {
                        throw "Unable to find extension deployment status"
                    }
                    $thisExtension | ForEach-Object {
                        if ($_.status -ne $lastStatus) {
                            Write-Host $_.status
                            $lastStatus = $_.status
                        }
                        if ($_.status -eq "InProgress") {
                            $errCount = 0
                            $sleepSeconds = 5
                        }
                        elseif ($_.Status -eq "Unknown") {
                            throw "Unknown Error"
                        }
                        elseif ($_.Status -eq "Completed") {
                            $completed = $true
                        }
                        else {
                            $errCount = 5
                            throw $_.status
                        }
                    }
                }
                catch {
                    if ($errCount++ -gt 4) {
                        Write-Host $_.Exception.Message
                        throw "Unable to publish app. Please open the Extension Deployment Status Details page in Business Central to see the detailed error message."
                    }
                    $sleepSeconds += $sleepSeconds
                    Write-Host "Error: $($_.Exception.Message). Retrying in $sleepSeconds seconds"
                }
            }
        }
    }
    catch {
        Write-Host "ERROR: $($_.Exception.Message)"
        throw (Get-BCDevOpsFlowsExtendedErrorMessage -errorRecord $_)
    }
    finally {
        $extensions = (Invoke-RestMethodWithRetry -parameters @{ "Headers" = (Get-BCDevOpsFlowsAuthHeaders -authContext $authContext); "Method" = 'Get'; "Uri" = "$automationApiUrl/companies($companyId)/extensions"; "UseBasicParsing" = $true }).value | Sort-Object -Property displayName
        Write-Host "Extensions after:"
        $extensions | ForEach-Object { Write-Host " - $($_.DisplayName), Version $($_.versionMajor).$($_.versionMinor).$($_.versionBuild).$($_.versionRevision), Installed=$($_.isInstalled)" }
    }
}

# Publishes an app through the developer endpoint (dev scope), mirroring
# BcContainerHelper's Publish-BcContainerApp -useDevEndpoint for online environments
function Publish-BCDevOpsFlowsDevEndpointApp {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $authContext,
        [Parameter(Mandatory = $true)]
        [string] $environment,
        [Parameter(Mandatory = $true)]
        [string] $appFile,
        [Parameter(Mandatory = $false)]
        [string] $syncMode = 'Add',
        [switch] $checkAlreadyInstalled
    )

    if ($checkAlreadyInstalled) {
        # PublishedAs is either 'Global', ' PTE' or ' Dev' (with leading space)
        $installedApps = @(Get-BCDevOpsFlowsInstalledExtensions -authContext $authContext -environment $environment |
                Where-Object { $_.isInstalled -and "$($_.publishedAs)".Trim() -ne 'Dev' } | ForEach-Object {
                    @{ "id" = $_.id; "version" = [System.Version]::new($_.versionMajor, $_.versionMinor, $_.versionBuild, $_.versionRevision) }
                })
        $sortedAppFiles = @(Sort-BCDevOpsFlowsAppFilesByDependencies -appFiles @($appFile) -excludeInstalledApps $installedApps)
        if ($sortedAppFiles.Count -eq 0) {
            return
        }
    }

    $schemaUpdateMode = "synchronize"
    if ($syncMode -eq "Clean") {
        $schemaUpdateMode = "recreate"
    }
    elseif ($syncMode -eq "ForceSync") {
        $schemaUpdateMode = "forcesync"
    }
    $devServerUrl = "$((Get-BCDevOpsFlowsApiBaseUrl).TrimEnd('/'))/v2.0/$environment"
    $url = "$devServerUrl/dev/apps?SchemaUpdateMode=$schemaUpdateMode"
    $appName = [System.IO.Path]::GetFileName($appFile)

    Update-BCDevOpsFlowsAuthContext -authContext $authContext | Out-Null
    $handler = New-Object System.Net.Http.HttpClientHandler
    $httpClient = [System.Net.Http.HttpClient]::new($handler)
    try {
        $httpClient.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $authContext.AccessToken)
        $httpClient.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
        $httpClient.DefaultRequestHeaders.ExpectContinue = $false

        $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
        $fileStream = [System.IO.FileStream]::new($appFile, [System.IO.FileMode]::Open)
        try {
            $fileHeader = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data")
            $fileHeader.Name = "$appName"
            $fileHeader.FileName = "$appName"
            $fileHeader.FileNameStar = "$appName"
            $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
            $fileContent.Headers.ContentDisposition = $fileHeader
            $multipartContent.Add($fileContent)
            Write-Host "Publishing $appName to $url"
            $result = $httpClient.PostAsync($url, $multipartContent).GetAwaiter().GetResult()
            if (!$result.IsSuccessStatusCode) {
                $message = "Status Code $($result.StatusCode) : $($result.ReasonPhrase)"
                try {
                    $resultMsg = $result.Content.ReadAsStringAsync().Result
                    try {
                        $json = $resultMsg | ConvertFrom-Json
                        $message += "`n$($json.Message)"
                    }
                    catch {
                        $message += "`n$resultMsg"
                    }
                }
                catch {
                }
                throw $message
            }
        }
        finally {
            $fileStream.Close()
        }
    }
    finally {
        $httpClient.Dispose()
    }
}

# Installs an AppSource app through the admin center API, mirroring
# BcContainerHelper's Install-BcAppFromAppSource
function Install-BCDevOpsFlowsAppFromAppSource {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $authContext,
        [Parameter(Mandatory = $true)]
        [string] $environment,
        [Parameter(Mandatory = $true)]
        [string] $appId,
        [switch] $acceptIsvEula,
        [switch] $installOrUpdateNeededDependencies
    )

    $adminApiUrl = "$((Get-BCDevOpsFlowsApiBaseUrl).TrimEnd('/'))/admin/v2.6/applications/BusinessCentral/environments"
    $bcEnvironment = (Invoke-RestMethodWithRetry -parameters @{ "Headers" = (Get-BCDevOpsFlowsAuthHeaders -authContext $authContext); "Method" = 'Get'; "Uri" = $adminApiUrl; "UseBasicParsing" = $true }).value | Where-Object { $_.name -eq $environment }
    if (!$bcEnvironment) {
        throw "Environment $environment doesn't exist in the current context."
    }
    if ($bcEnvironment.type -eq 'Production') {
        throw "Dependency AppSource apps cannot be installed on a production environment by this step. Install the app through the admin center instead."
    }
    $publishedApps = (Invoke-RestMethodWithRetry -parameters @{ "Headers" = (Get-BCDevOpsFlowsAuthHeaders -authContext $authContext); "Method" = 'Get'; "Uri" = "$adminApiUrl/$environment/apps"; "UseBasicParsing" = $true }).value
    $appExists = $publishedApps | Where-Object { $_.id -eq $appId -and $_.state -eq "installed" }
    if ($appExists) {
        Write-Host -ForegroundColor Green "App $($appExists.name) from $($appExists.publisher) version $($appExists.version) is already installed"
        return
    }

    $response = Invoke-RestMethodWithRetry -parameters @{ "Method" = 'Get'; "Uri" = "$((Get-BCDevOpsFlowsBaseUrl).TrimEnd('/'))/$($authContext.tenantID)/$environment/deployment/url"; "UseBasicParsing" = $true }
    if ($response.status -ne 'Ready') {
        throw "environment not ready, status is $($response.status)"
    }

    $body = @{ "AcceptIsvEula" = $acceptIsvEula.ToBool() }
    if ($installOrUpdateNeededDependencies) {
        $body += @{ "installOrUpdateNeededDependencies" = $installOrUpdateNeededDependencies.ToBool() }
    }
    Write-Host "Installing $appId on $($environment)"
    try {
        $operation = Invoke-RestMethod -Method Post -UseBasicParsing -Uri "$adminApiUrl/$environment/apps/$appId/install" -Headers (Get-BCDevOpsFlowsAuthHeaders -authContext $authContext) -ContentType "application/json" -Body ($body | ConvertTo-Json) -TimeoutSec 300
    }
    catch {
        throw (Get-BCDevOpsFlowsExtendedErrorMessage -errorRecord $_)
    }

    Write-Host "Operation ID $($operation.id)"
    $status = $operation.status
    Write-Host "$($status)."
    $completed = $operation.status -eq "succeeded"
    $errCount = 0
    while (-not $completed) {
        Start-Sleep -Seconds 3
        try {
            $appInstallStatuses = (Invoke-RestMethod -Headers (Get-BCDevOpsFlowsAuthHeaders -authContext $authContext) -Method Get -Uri "$adminApiUrl/$environment/apps/$appId/operations" -UseBasicParsing -TimeoutSec 300).value
            $appInstallStatus = $appInstallStatuses | Where-Object { $_.id -eq $operation.id }
            if ($status -ne $appInstallStatus.status) {
                Write-Host "$($appInstallStatus.status)"
                $status = $appInstallStatus.status
            }
            $completed = $status -eq "succeeded"
            if (!$completed -and $status -ne "running" -and $status -ne "scheduled") {
                $errorMessage = $status
                try {
                    $appInstallStatus | ForEach-Object { if ($_.errorMessage) { $errorMessage = $_.errorMessage } }
                }
                catch {
                }
                throw $errorMessage
            }
            $errCount = 0
        }
        catch {
            if ($errCount++ -gt 3) {
                throw (Get-BCDevOpsFlowsExtendedErrorMessage -errorRecord $_)
            }
            $completed = $false
        }
    }
}
