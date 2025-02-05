function Set-GitUser {
    invoke-git config --global user.email "BCDevOpsFlows@dev.azure.com"
    invoke-git config --global user.name "BCDevOps Flows Pipeline"
}
function Invoke-RestoreUnstagedChanges {
    Param(
        [string] $appFilePath
    )
    invoke-git restore $appFilePath
}
function Invoke-GitAddCommitPush {
    Param(
        [string] $appFilePath,
        [string] $commitMessage,
        [string] $targetBranch = "HEAD:$($ENV:BUILD_SOURCEBRANCH)"
    )

    invoke-git add $appFilePath

    if ($commitMessage -eq '') {
        $commitMessage = "BCDevOps Flows Update [skip azurepipelines]"
    }
    else {
        $commitMessage = "$commitMessage [skip azurepipelines]"
    }
    invoke-git commit -m $commitMessage
    invoke-git push origin $targetBranch
}
