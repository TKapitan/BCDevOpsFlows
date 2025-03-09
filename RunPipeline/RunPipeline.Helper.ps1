. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

function GetContainerName() {
    "bc-$($ENV:BUILD_REPOSITORY_NAME -replace "[^a-z0-9]")-$ENV:BUILD_BUILDID"
}
