function GetContainerName() {
    "bc-$($ENV:BUILD_REPOSITORY_NAME -replace "[^a-z0-9]")-$ENV:BUILD_BUILDID"
}