$script:errors = @()
$script:warnings = @()
$script:suggestions = @()
$script:debugMessages = @()

function OutputMessageDebug {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if (!$ENV:AL_DEBUGMODE) {
        return;
    }

    $script:debugMessages += "- $Message"
    Write-Host "::Debug::$Message"
}

function OutputMessage {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host $Message
}

function OutputMessageWarning {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $script:warnings += "- $Message"
    Write-Host "- Warning: $Message"
}

function OutputMessageError {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $script:errors += "- $Message"
    Write-Host "- Error: $Message"
}

function OutputMessageSuggestion {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $script:suggestions += "- $Message"
    Write-Host "- Suggestion: $Message"
}

function OutputWarning {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $script:warnings += "- $Message"
    Write-Warning "Warning: $Message"
}

function OutputError {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $script:errors += "- $Message"
    Write-Error "Error: $Message"
}