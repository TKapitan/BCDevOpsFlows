# Copy of NuGet class from BCContainerHelper, required changed to support Azure DevOps preview packages
#requires -Version 5.0

class BcDevOpsFlowsNuGetFeed {

    [string] $url
    [string] $token
    [string[]] $patterns
    [string[]] $fingerprints

    [string] $searchQueryServiceUrl
    [string] $packagePublishUrl
    [string] $packageBaseAddressUrl

    [hashtable] $orgType = @{}

    # Feed instances are cached per (url, token, patterns, fingerprints) to avoid repeating
    # the service index request in the constructor for every package lookup
    static [hashtable] $feedInstanceCache = @{}

    BcDevOpsFlowsNuGetFeed([string] $nuGetServerUrl, [string] $nuGetToken, [string[]] $patterns, [string[]] $fingerprints) {
        $this.url = $nuGetServerUrl
        $this.token = $nuGetToken
        $this.patterns = $patterns
        $this.fingerprints = $fingerprints

        # When trusting nuget.org, you should only trust packages signed by an author or packages matching a specific pattern (like using a registered prefix or a full name)
        if ($nuGetServerUrl -like 'https://api.nuget.org/*' -and $patterns.Contains('*') -and (!$fingerprints -or $fingerprints.Contains('*'))) {
            throw "Trusting all packages on nuget.org is not supported"
        }

        try {
            $prev = $global:ProgressPreference; $global:ProgressPreference = "SilentlyContinue"
            $capabilities = Invoke-RestMethod -UseBasicParsing -Method GET -Headers ($this.GetHeaders()) -Uri $this.url
            $global:ProgressPreference = $prev
            $this.searchQueryServiceUrl = $capabilities.resources | Where-Object { $_.'@type' -eq 'SearchQueryService' } | Select-Object -ExpandProperty '@id' | Select-Object -First 1
            if (!$this.searchQueryServiceUrl) {
                # Azure DevOps doesn't support SearchQueryService, but SearchQueryService/3.0.0-beta
                $this.searchQueryServiceUrl = $capabilities.resources | Where-Object { $_.'@type' -eq 'SearchQueryService/3.0.0-beta' } | Select-Object -ExpandProperty '@id' | Select-Object -First 1
            }
            $this.packagePublishUrl = $capabilities.resources | Where-Object { $_."@type" -eq 'PackagePublish/2.0.0' } | Select-Object -ExpandProperty '@id' | Select-Object -First 1
            $this.packageBaseAddressUrl = $capabilities.resources | Where-Object { $_."@type" -eq 'PackageBaseAddress/3.0.0' } | Select-Object -ExpandProperty '@id' | Select-Object -First 1
            if (!$this.searchQueryServiceUrl -or !$this.packagePublishUrl -or !$this.packageBaseAddressUrl) {
                Write-Host "Capabilities of NuGet server $($this.url) are not supported"
                $capabilities.resources | ForEach-Object { Write-Host "- $($_.'@type')"; Write-Host "-> $($_.'@id')" }
            }
            Write-Verbose "Capabilities of NuGet server $($this.url) are:"
            Write-Verbose "- SearchQueryService=$($this.searchQueryServiceUrl)"
            Write-Verbose "- PackagePublish=$($this.packagePublishUrl)"
            Write-Verbose "- PackageBaseAddress=$($this.packageBaseAddressUrl)"
        }
        catch {
            Write-Host "##vso[task.logissue type=error]$($_.Exception.Message)"
            Write-Host $_.ScriptStackTrace
            if ($_.PSMessageDetails) {
                Write-Host $_.PSMessageDetails
            }
            Write-Host "##vso[task.complete result=Failed]"
            throw ($_.Exception.Message)
        }
    }

    static [BcDevOpsFlowsNuGetFeed] Create([string] $nuGetServerUrl, [string] $nuGetToken, [string[]] $patterns, [string[]] $fingerprints) {
        $cacheKey = "$nuGetServerUrl|$nuGetToken|$($patterns -join ',')|$($fingerprints -join ',')"
        if ([BcDevOpsFlowsNuGetFeed]::feedInstanceCache.ContainsKey($cacheKey)) {
            return [BcDevOpsFlowsNuGetFeed]::feedInstanceCache[$cacheKey]
        }
        $nuGetFeed = [BcDevOpsFlowsNuGetFeed]::new($nuGetServerUrl, $nuGetToken, $patterns, $fingerprints)
        [BcDevOpsFlowsNuGetFeed]::feedInstanceCache[$cacheKey] = $nuGetFeed
        return $nuGetFeed
    }

    [void] Dump([string] $message) {
        Write-Host $message
    }

    [hashtable] GetHeaders() {
        $headers = @{
            "Content-Type" = "application/json; charset=utf-8"
        }
        # nuget.org only support anonymous access
        if ($this.token -and $this.url -notlike 'https://api.nuget.org/*') {
            $headers += @{
                "Authorization" = "Basic $([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("user:$($this.token)")))"
            }
        }
        return $headers
    }

    [bool] IsTrusted([string] $packageId) {
        return ($packageId -and ($this.patterns | Where-Object { $packageId -like $_ }))
    }

    [hashtable[]] Search([string] $packageName, [bool] $allowPrerelease) {
        if ($this.searchQueryServiceUrl -match '^https://nuget.pkg.github.com/(.*)/query$') {
            # GitHub support for SearchQueryService is unstable and is not usable
            # use GitHub API instead
            # GitHub API unfortunately doesn't support filtering, so we need to filter ourselves
            $organization = $matches[1]
            $headers = @{
                "Accept"               = "application/vnd.github+json"
                "X-GitHub-Api-Version" = "2022-11-28"
            }
            if ($this.token) {
                $headers += @{
                    "Authorization" = "Bearer $($this.token)"
                }
            }
            if (-not $this.orgType.ContainsKey($organization)) {
                $orgMetadata = Invoke-RestMethod -Method GET -Headers $headers -Uri "https://api.github.com/users/$organization"
                if ($orgMetadata.type -eq 'Organization') {
                    $this.orgType[$organization] = 'orgs'
                }
                else {
                    $this.orgType[$organization] = 'users'
                }
            }
            $queryUrl = "https://api.github.com/$($this.orgType[$organization])/$organization/packages?package_type=nuget&per_page=100&page="
            $page = 1
            Write-Host -ForegroundColor Yellow "Search package using $queryUrl$page"
            $matching = @()
            while ($true) {
                $result = Invoke-RestMethod -Method GET -Headers $headers -Uri "$queryUrl$page"
                if ($result.Count -eq 0) {
                    break
                }
                $matching += @($result | Where-Object { $_.name -like "*$packageName*" -and $this.IsTrusted($_.name) } | Sort-Object { $_.name.replace('.symbols', '') } | ForEach-Object { @{ "id" = $_.name; "versions" = @() } } )
                $page++
            }
        }
        else {
            if ($allowPrerelease) {
                $queryUrl = "$($this.searchQueryServiceUrl)?q=$packageName&prerelease=true&take=50"
            }
            else {
                $queryUrl = "$($this.searchQueryServiceUrl)?q=$packageName&prerelease=false&take=50"
            }
            try {
                Write-Host -ForegroundColor Yellow "Search package using $queryUrl"
                $prev = $global:ProgressPreference; $global:ProgressPreference = "SilentlyContinue"
                $searchResult = Invoke-RestMethod -UseBasicParsing -Method GET -Headers ($this.GetHeaders()) -Uri $queryUrl
                $global:ProgressPreference = $prev
            }
            catch {
                Write-Host "##vso[task.logissue type=error]$($_.Exception.Message)"
                Write-Host $_.ScriptStackTrace
                if ($_.PSMessageDetails) {
                    Write-Host $_.PSMessageDetails
                }
                Write-Host "##vso[task.complete result=Failed]"
                throw ($_.Exception.Message)
            }
            # Check that the found pattern matches the package name and the trusted patterns
            $matching = @($searchResult.data | Where-Object { $_.id -like "*$($packageName)*" -and $this.IsTrusted($_.id) } | Sort-Object { $_.id.replace('.symbols', '') } | ForEach-Object { @{ "id" = $_.id; "versions" = @($_.versions.version) } } )
        }
        $exact = $matching | Where-Object { $_.id -eq $packageName -or $_.id -eq "$packageName.symbols" }
        if ($exact) {
            Write-Host "Exact match found for $packageName"
            $matching = $exact
        }
        else {
            Write-Host "$($matching.count) matching packages found"
        }
        return $matching | ForEach-Object { Write-Host "- $($_.id)"; $_ }
    }

    # Resolve exact package ids directly via the flat container API (PackageBaseAddress) instead of the
    # search service. The search service is slow on Azure DevOps, unstable on GitHub and truncates results,
    # so exact ids ($packageName and $packageName.symbols) are probed directly. Returns the same shape as
    # Search(); an empty result means the caller must fall back to Search() to keep partial-name matching.
    [hashtable[]] GetExactPackages([string] $packageName) {
        $result = @()
        if (!$this.packageBaseAddressUrl) {
            return $result
        }
        foreach ($packageId in @($packageName, "$packageName.symbols")) {
            if (!$this.IsTrusted($packageId)) {
                continue
            }
            $queryUrl = "$($this.packageBaseAddressUrl.TrimEnd('/'))/$($packageId.ToLowerInvariant())/index.json"
            $prev = $global:ProgressPreference; $global:ProgressPreference = "SilentlyContinue"
            try {
                Write-Host -ForegroundColor Yellow "Get exact package using $queryUrl"
                $versions = Invoke-RestMethod -UseBasicParsing -Method GET -Headers ($this.GetHeaders()) -Uri $queryUrl
                if ($versions -and $versions.versions) {
                    Write-Host "Exact match found for $packageId"
                    $result += @{ "id" = $packageId; "versions" = @($versions.versions) }
                }
            }
            catch {
                # 404 (or any other error) - the package id doesn't resolve on this feed; the caller falls back to search
                Write-Verbose "Package $packageId not found using $queryUrl ($($_.Exception.Message))"
            }
            finally {
                $global:ProgressPreference = $prev
            }
        }
        return $result
    }

    [string[]] GetVersions([hashtable] $package, [bool] $descending, [bool] $allowPrerelease) {
        if (!$this.IsTrusted($package.id)) {
            throw "Package $($package.id) is not trusted on $($this.url)"
        }
        if ($package.versions.count -ne 0) {
            $versionsArr = $package.versions
        }
        else {
            $queryUrl = "$($this.packageBaseAddressUrl.TrimEnd('/'))/$($package.Id.ToLowerInvariant())/index.json"
            try {
                Write-Host -ForegroundColor Yellow "Get versions using $queryUrl"
                $prev = $global:ProgressPreference; $global:ProgressPreference = "SilentlyContinue"
                $versions = Invoke-RestMethod -UseBasicParsing -Method GET -Headers ($this.GetHeaders()) -Uri $queryUrl
                $global:ProgressPreference = $prev
            }
            catch {
                Write-Host "##vso[task.logissue type=error]$($_.Exception.Message)"
                Write-Host $_.ScriptStackTrace
                if ($_.PSMessageDetails) {
                    Write-Host $_.PSMessageDetails
                }
                Write-Host "##vso[task.complete result=Failed]"
                throw ($_.Exception.Message)
            }
            $versionsArr = @($versions.versions)
    
        }
        Write-Host "$($versionsArr.count) versions found"
        $versionsArr = @($versionsArr | Where-Object { $allowPrerelease -or !$_.Contains('-') } | Sort-Object { ($_ -replace '-.+$') -as [System.Version] }, { "$($_)z" } -Descending:$descending | ForEach-Object { "$_" })
        Write-Host "First version is $($versionsArr[0])"
        Write-Host "Last version is $($versionsArr[$versionsArr.Count-1])"
        return $versionsArr
    }

    # Normalize name or publisher name to be used in nuget id
    static [string] Normalize([string] $name) {
        return $name -replace '[^a-zA-Z0-9_\-]', ''
    }

    static [string] NormalizeVersionStr([string] $versionStr) {
        $idx = $versionStr.IndexOf('-')
        $version = [System.version]($versionStr.Split('-')[0])
        if ($version.Build -eq -1) { $version = [System.Version]::new($version.Major, $version.Minor, 0, 0) }
        if ($version.Revision -eq -1) { $version = [System.Version]::new($version.Major, $version.Minor, $version.Build, 0) }
        if ($idx -gt 0) {
            return "$version$($versionStr.Substring($idx))"
        }
        else {
            return "$version"
        }
    }

    static [Int32] CompareVersions([string] $version1, [string] $version2) {
        $version1 = [BcDevOpsFlowsNuGetFeed]::NormalizeVersionStr($version1)
        $version2 = [BcDevOpsFlowsNuGetFeed]::NormalizeVersionStr($version2)
        $ver1 = $version1 -replace '-.+$' -as [System.Version]
        $ver2 = $version2 -replace '-.+$' -as [System.Version]
        if ($ver1 -eq $ver2) {
            # add a 'z' to the version to make sure that 5.1.0 is greater than 5.1.0-beta
            # Tags are sorted alphabetically (alpha, beta, rc, etc.), even though this shouldn't matter
            # New prerelease versions will always have a new version number
            # [string]::Compare can return any integer; callers compare against -1/0/1, so normalize
            return [Math]::Sign([string]::Compare("$($version1)z", "$($version2)z"))
        }
        elseif ($ver1 -gt $ver2) {
            return 1
        }
        else {
            return -1
        }
    }

    # Test if version is included in NuGet version range
    # https://learn.microsoft.com/en-us/nuget/concepts/package-versioning#version-ranges
    static [bool] IsVersionIncludedInRange([string] $versionStr, [string] $nuGetVersionRange) {
        $versionStr = [BcDevOpsFlowsNuGetFeed]::NormalizeVersionStr($versionStr)
        $version = $versionStr -replace '-.+$' -as [System.Version]
        if ($nuGetVersionRange -match '^\s*([\[(]?)([\d\.]*)(,?)([\d\.]*)([\])]?)\s*$') {
            $inclFrom = $matches[1] -ne '('
            $range = $matches[3] -eq ','
            $inclTo = $matches[5] -eq ']'
            if ($matches[1] -eq '' -and $matches[5] -eq '') {
                $range = $true
            }
            if ($matches[2]) {
                $fromver = [System.Version]([BcDevOpsFlowsNuGetFeed]::NormalizeVersionStr($matches[2]))
            }
            else {
                $fromver = [System.Version]::new(0, 0, 0, 0)
                if ($inclFrom) {
                    Write-Host "Invalid NuGet version range $nuGetVersionRange"
                    return $false
                }
            }
            if ($matches[4]) {
                $tover = [System.Version]([BcDevOpsFlowsNuGetFeed]::NormalizeVersionStr($matches[4]))
            }
            elseif ($range) {
                $tover = [System.Version]::new([int32]::MaxValue, [int32]::MaxValue, [int32]::MaxValue, [int32]::MaxValue)
                if ($inclTo) {
                    Write-Host "Invalid NuGet version range $nuGetVersionRange"
                    return $false
                }
            }
            else {
                $tover = $fromver
            }
            if (!$range -and (!$inclFrom -or !$inclTo)) {
                Write-Host "Invalid NuGet version range $nuGetVersionRange"
                return $false
            }
            if ($inclFrom) {
                if ($inclTo) {
                    return $version -ge $fromver -and $version -le $tover
                }
                else {
                    return $version -ge $fromver -and $version -lt $tover
                }
            }
            else {
                if ($inclTo) {
                    return $version -gt $fromver -and $version -le $tover
                }
                else {
                    return $version -gt $fromver -and $version -lt $tover
                }
            }
        }
        return $false
    }

    [string] FindPackageVersion([hashtable] $package, [string] $nuGetVersionRange, [string[]] $excludeVersions, [string] $select, [bool] $allowPrerelease) {
        $versions = $this.GetVersions($package, ($select -ne 'Earliest'), $allowPrerelease)
        if ($excludeVersions) {
            Write-Host "Exclude versions: $($excludeVersions -join ', ')"
        }
        foreach ($version in $versions) {
            if ($excludeVersions -contains $version) {
                continue
            }
            if (($select -eq 'Exact' -and [BcDevOpsFlowsNuGetFeed]::NormalizeVersionStr($nuGetVersionRange) -eq [BcDevOpsFlowsNuGetFeed]::NormalizeVersionStr($version)) -or ($select -ne 'Exact' -and [BcDevOpsFlowsNuGetFeed]::IsVersionIncludedInRange($version, $nuGetVersionRange))) {
                if ($nuGetVersionRange -eq '0.0.0.0') {
                    Write-Host "$select version is $version"
                }
                else {
                    Write-Host "$select version matching '$nuGetVersionRange' is $version"
                }
                return $version
            }
        }
        return ''
    }

    [xml] DownloadNuSpec([string] $packageId, [string] $version) {
        if (!$this.IsTrusted($packageId)) {
            throw "Package $packageId is not trusted on $($this.url)"
        }
        $queryUrl = "$($this.packageBaseAddressUrl.TrimEnd('/'))/$($packageId.ToLowerInvariant())/$($version.ToLowerInvariant())/$($packageId.ToLowerInvariant()).nuspec"
        try {
            Write-Host "Download nuspec using $queryUrl"
            $prev = $global:ProgressPreference; $global:ProgressPreference = "SilentlyContinue"
            $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "$([GUID]::NewGuid().ToString()).nuspec"
            Invoke-RestMethod -UseBasicParsing -Method GET -Headers ($this.GetHeaders()) -Uri $queryUrl -OutFile $tmpFile
            $nuspec = Get-Content -Path $tmpfile -Encoding UTF8 -Raw
            Remove-Item -Path $tmpFile -Force
            $global:ProgressPreference = $prev
        }
        catch {
            Write-Host "##vso[task.logissue type=error]$($_.Exception.Message)"
            Write-Host $_.ScriptStackTrace
            if ($_.PSMessageDetails) {
                Write-Host $_.PSMessageDetails
            }
            Write-Host "##vso[task.complete result=Failed]"
            throw ($_.Exception.Message)
        }
        return [xml]$nuspec
    }

    # Path to the persistent package content cache entry for a package version, or '' if caching is disabled.
    # A package version's content is immutable, so cached content can be reused across runs without
    # compromising version resolution - the version to use is always resolved online first.
    hidden [string] GetPackageCacheFolder([string] $packageId, [string] $version) {
        try {
            if (!$ENV:AL_SETTINGS) {
                return ''
            }
            $settings = $ENV:AL_SETTINGS | ConvertFrom-Json
            if (!$settings.writableFolderPath) {
                return ''
            }
            if (($settings.PSObject.Properties.Name -contains 'nugetPackageCacheKeepDays') -and ([int]$settings.nugetPackageCacheKeepDays -eq 0)) {
                return ''
            }
            # Cache is scoped per feed - the same package id/version from a different feed is verified and cached separately
            $feedHash = [BcDevOpsFlowsNuGetFeed]::GetUrlHash($this.url)
            return (Join-Path $settings.writableFolderPath ".nuget/bcpackages/$feedHash/$($packageId.ToLowerInvariant())/$($version.ToLowerInvariant())")
        }
        catch {
            return ''
        }
    }

    static [string] GetUrlHash([string] $url) {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        try {
            $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($url.ToLowerInvariant()))
            return [BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant().Substring(0, 12)
        }
        finally {
            $md5.Dispose()
        }
    }

    # Copy the extracted package content into the persistent cache. Best effort - a failure to cache
    # must never fail the download. The marker file flags the entry as complete; content is staged in a
    # temporary sibling folder and renamed into place so other processes never see a partial entry.
    hidden [void] AddPackageToCache([string] $packageFolder, [string] $cacheFolder, [string] $packageId, [string] $version) {
        $cacheMutex = New-Object System.Threading.Mutex($false, "BCDevOpsFlowsPackageCache-$($packageId.ToLowerInvariant())-$($version.ToLowerInvariant())")
        try {
            try {
                if (!$cacheMutex.WaitOne(1000)) {
                    Write-Host "Waiting for other process caching $packageId ($version)"
                    $cacheMutex.WaitOne() | Out-Null
                    Write-Host "Other process completed caching $packageId ($version)"
                }
            }
            catch [System.Threading.AbandonedMutexException] {
                Write-Host "Other process terminated abnormally"
            }
            if (Test-Path (Join-Path $cacheFolder '.bcdevopsflows.complete') -PathType Leaf) {
                return
            }
            if (Test-Path $cacheFolder) {
                # Incomplete cache entry (no marker file) - rebuild it
                Remove-Item -Path $cacheFolder -Recurse -Force
            }
            $parentFolder = Split-Path $cacheFolder -Parent
            if (!(Test-Path $parentFolder)) {
                New-Item -Path $parentFolder -ItemType Directory -Force | Out-Null
            }
            $stagingFolder = "$cacheFolder-$([GUID]::NewGuid().ToString('N'))"
            Copy-Item -Path $packageFolder -Destination $stagingFolder -Recurse -Force
            Set-Content -Path (Join-Path $stagingFolder '.bcdevopsflows.complete') -Value ([DateTime]::UtcNow.ToString('o'))
            try {
                Rename-Item -Path $stagingFolder -NewName (Split-Path $cacheFolder -Leaf)
                Write-Host "Cached package $packageId ($version) at $cacheFolder"
            }
            catch {
                # Another process (on another machine) cached the package first
                Remove-Item -Path $stagingFolder -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Host "WARNING: Could not cache package $packageId ($version): $($_.Exception.Message)"
        }
        finally {
            $cacheMutex.ReleaseMutex()
            $cacheMutex.Close()
        }
    }

    [string] DownloadPackage([string] $packageId, [string] $version) {
        if (!$this.IsTrusted($packageId)) {
            throw "Package $packageId is not trusted on $($this.url)"
        }
        $tmpFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
        $cacheFolder = $this.GetPackageCacheFolder($packageId, $version)
        if ($cacheFolder -and (Test-Path (Join-Path $cacheFolder '.bcdevopsflows.complete') -PathType Leaf)) {
            try {
                Write-Host -ForegroundColor Green "Using cached package $packageId ($version) from $cacheFolder"
                Copy-Item -Path $cacheFolder -Destination $tmpFolder -Recurse -Force
                Remove-Item -Path (Join-Path $tmpFolder '.bcdevopsflows.complete') -Force
                try { (Get-Item $cacheFolder).LastWriteTimeUtc = [DateTime]::UtcNow } catch { }
                return $tmpFolder
            }
            catch {
                Write-Host "WARNING: Failed to read cached package $packageId ($version): $($_.Exception.Message). Re-downloading."
                if (Test-Path $tmpFolder) {
                    Remove-Item -Path $tmpFolder -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        $queryUrl = "$($this.packageBaseAddressUrl.TrimEnd('/'))/$($packageId.ToLowerInvariant())/$($version.ToLowerInvariant())/$($packageId.ToLowerInvariant()).$($version.ToLowerInvariant()).nupkg"
        try {
            Write-Host -ForegroundColor Green "Download package using $queryUrl"
            $prev = $global:ProgressPreference; $global:ProgressPreference = "SilentlyContinue"
            $filename = "$tmpFolder.zip"
            Invoke-RestMethod -UseBasicParsing -Method GET -Headers ($this.GetHeaders()) -Uri $queryUrl -OutFile $filename
            if ($this.fingerprints) {
                $arguments = @("nuget", "verify", $filename)
                if ($this.fingerprints.Count -eq 1 -and $this.fingerprints[0] -eq '*') {
                    Write-Host "Verifying package using any certificate"
                }
                else {
                    Write-Host "Verifying package using $($this.fingerprints -join ', ')"
                    $arguments += @("--certificate-fingerprint $($this.fingerprints -join ' --certificate-fingerprint ')")
                }
                cmddo -command 'dotnet' -arguments $arguments -silent -messageIfCmdNotFound "dotnet not found. Please install it from https://dotnet.microsoft.com/download"
            }
            Expand-Archive -Path $filename -DestinationPath $tmpFolder -Force
            $global:ProgressPreference = $prev
            Remove-Item $filename -Force
            Write-Host "Package successfully downloaded"
        }
        catch {
            Write-Host "##vso[task.logissue type=error]$($_.Exception.Message)"
            Write-Host $_.ScriptStackTrace
            if ($_.PSMessageDetails) {
                Write-Host $_.PSMessageDetails
            }
            Write-Host "##vso[task.complete result=Failed]"
            throw ($_.Exception.Message)
        }
        if ($cacheFolder) {
            $this.AddPackageToCache($tmpFolder, $cacheFolder, $packageId, $version)
        }
        return $tmpFolder
    }

    [void] PushPackage([string] $package) {
        if (!($this.token)) {
            throw "NuGet token is required to push packages"
        }
        Write-Host "Preparing NuGet Package for submission"
        $headers = $this.GetHeaders()
        $headers += @{
            "X-NuGet-ApiKey"         = $this.token
            "X-NuGet-Client-Version" = "6.3.0"
        }
        $boundary = [System.Guid]::NewGuid().ToString();
        $LF = "`r`n";
        $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
        $fs = [System.IO.File]::OpenWrite($tmpFile)
        $fs | Add-Member -MemberType ScriptMethod -Name WriteBytes -Value { param($bytes) $this.Write($bytes, 0, $bytes.Length) }
        try {
            $fs.WriteBytes([System.Text.Encoding]::UTF8.GetBytes("--$boundary$LF"))
            $fs.WriteBytes([System.Text.Encoding]::UTF8.GetBytes("Content-Type: application/octet-stream$($LF)Content-Disposition: form-data; name=package; filename=""$([System.IO.Path]::GetFileName($package))""$($LF)$($LF)"))
            $fs.WriteBytes([System.IO.File]::ReadAllBytes($package))
            $fs.WriteBytes([System.Text.Encoding]::UTF8.GetBytes("$LF--$boundary--$LF"))
        }
        finally {
            $fs.Close()
        }
        
        Write-Host "Submitting NuGet package"
        try {
            Invoke-RestMethod -UseBasicParsing -Uri $this.packagePublishUrl -ContentType "multipart/form-data; boundary=$boundary" -Method Put -Headers $headers -inFile $tmpFile | Out-Host
            Write-Host -ForegroundColor Green "NuGet package successfully submitted"
        }
        catch {
            # Windows PowerShell raises System.Net.WebException, PowerShell 7+ raises
            # Microsoft.PowerShell.Commands.HttpResponseException; both expose the HTTP status
            # through $_.Exception.Response.StatusCode
            $statusCode = $null
            try {
                if ($_.Exception.Response) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
            }
            catch {
                $statusCode = $null
            }
            if ($statusCode -eq 409) {
                Write-Host -ForegroundColor Yellow "NuGet package already exists"
            }
            else {
                Write-Host "##vso[task.logissue type=error]$($_.Exception.Message)"
                Write-Host $_.ScriptStackTrace
                if ($_.PSMessageDetails) {
                    Write-Host $_.PSMessageDetails
                }
                Write-Host "##vso[task.complete result=Failed]"
                throw ($_.Exception.Message)
            }
        }
        finally {
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        }
    
    }
}