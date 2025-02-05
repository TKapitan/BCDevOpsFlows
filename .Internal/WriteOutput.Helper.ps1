$script:errors = @()
$script:warnings = @()
$script:suggestions = @()
$script:debugMessages = @()

function OutputDebug {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if ($ENV:AL_DEBUG -ne 'true') {
        return;
    }
    $script:debugMessages += "- $Message"
    Write-Host "::Debug::$Message"
}

function OutputWarning {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $script:warnings += "- $Message"
    Write-Host "- Warning: $Message"
}

function OutputError {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $script:errors += "- $Message"
    Write-Host "- Error: $Message"
}

function OutputSuggestion {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $script:suggestions += "- $Message"
    Write-Host "- Suggestion: $Message"
}