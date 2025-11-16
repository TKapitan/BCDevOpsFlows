Param()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\Common\Import-Common.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\BCContainerHelper.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\.Internal\WriteOutput.Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "DetermineMajorVersion.Helper.ps1" -Resolve)

$settings = $ENV:AL_SETTINGS | ConvertFrom-Json | ConvertTo-HashTable

# Validate and parse artifact format
if ($settings.artifact -notmatch '^//([^/]*)//([^/]*)$') {
    throw "Invalid artifact format. Expected format: //ZZZ//YYY where only one of ZZZ or YYY should be populated."
}
$versionPart = $matches[1]
$keywordPart = $matches[2]
OutputDebug -Message "Parsed artifact - version part: '$versionPart', keyword part: '$keywordPart'"

# Ensure only one part is populated
if (![string]::IsNullOrEmpty($versionPart) -and ![string]::IsNullOrEmpty($keywordPart)) {
    throw "Both version and keyword parts are populated. Only one should be used."
}
if ([string]::IsNullOrEmpty($versionPart) -and [string]::IsNullOrEmpty($keywordPart)) {
    throw "Both version and keyword parts are empty. One must be populated."
}

if (![string]::IsNullOrEmpty($keywordPart)) {
    # Validate keyword
    $validKeywords = @('latest', 'nextmajor', 'appjson')
    if ($keywordPart.ToLowerInvariant() -notin $validKeywords) {
        throw "Invalid keyword '$keywordPart'. Valid keywords are: latest, nextMajor, appjson."
    }
    
    # Determine major version based on keyword
    $majorVersion = switch ($keywordPart.ToLowerInvariant()) {
        'latest' { 
            $currentMajorVersion = Get-CurrentMajorVersion
            $currentMajorVersion 
        }
        'nextmajor' { 
            $currentMajorVersion = Get-CurrentMajorVersion
            $currentMajorVersion + 1 
        }
        'appjson' {
            $appVersionParts = $($(Get-AppJson -settings $settings).application).Split('.')
            if ($appVersionParts.Count -eq 0 -or [string]::IsNullOrEmpty($appVersionParts[0])) {
                throw "Invalid application version format in app.json. Expected X.Y.Z.U format."
            }
            [int]$appVersionParts[0]
        }
    }
    OutputDebug -Message "Determined major version $majorVersion using keyword '$keywordPart'."
}
else {
    # Parse version and extract major version
    $versionParts = $versionPart.Split('.')
    if ($versionParts.Count -eq 0 -or [string]::IsNullOrEmpty($versionParts[0])) {
        throw "Invalid version format. Expected X.Y.Z.U format."
    }
    $majorVersion = [int]$versionParts[0]
    OutputDebug -Message "Extracted major version $majorVersion from version part '$versionPart'."
}

# Set output variables
OutputDebug -Message "Setting AL_ARTIFACT to $($settings.artifact) for NuGet build step."
OutputDebug -Message "Setting AL_BCMAJORVERSION to $majorVersion for NuGet build step."
$ENV:AL_ARTIFACT = $settings.artifact
Write-Host "##vso[task.setvariable variable=AL_ARTIFACT;]$($settings.artifact)"
OutputDebug -Message "Set environment variable AL_ARTIFACT to ($ENV:AL_ARTIFACT)"
$ENV:AL_BCMAJORVERSION = $majorVersion
Write-Host "##vso[task.setvariable variable=AL_BCMAJORVERSION;]$majorVersion"
OutputDebug -Message "Set environment variable AL_BCMAJORVERSION to ($ENV:AL_BCMAJORVERSION)"
