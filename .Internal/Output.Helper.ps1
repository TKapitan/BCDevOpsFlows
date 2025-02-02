$script:errors = @()
$script:warnings = @()
$script:suggestions = @()
$script:debugMessages = @()

function OutputMessageDebug {
    Param (
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [Object] $Message
    )

    if (!$ENV:AL_DEBUGMODE) {
        return;
    }

    $script:debugMessages += "- $Message"
    Write-Host "::Debug::$Message"
}

function OutputMessage {
    Param (
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [Object] $Message
    )

    Write-Host $Message
}

function OutputMessageWarning {
    Param (
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [Object] $Message
    )

    $script:warnings += "- $Message"
    Write-Host "- Warning: $Message"
}

function OutputMessageError {
    Param (
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [Object] $Message
    )

    $script:errors += "- $Message"
    Write-Host "- Error: $Message"
}

function OutputMessageSuggestion {
    Param (
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [Object] $Message
    )

    $script:suggestions += "- $Message"
    Write-Host "- Suggestion: $Message"
}

function OutputWarning {
    Param (
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [Object] $Message
    )

    $script:warnings += "- $Message"
    Write-Warning "Warning: $Message"
}

function OutputError {
    Param (
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [Object] $Message
    )

    $script:errors += "- $Message"
    Write-Error "Error: $Message"
}