. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Setup.ps1" -Resolve)

function Set-GitUser {
    invoke-git config --global user.email "BCDevOpsFlows@dev.azure.com"
    invoke-git config --global user.name "BCDevOps Flows Pipeline"
}
function Invoke-RestoreUnstagedChanges {
    Param(
        [string] $appFilePath
    )
    OutputDebug -Message "Restoring unstaged changes for $appFilePath"
    invoke-git restore $appFilePath
}
function Invoke-GitAddCommitPush {
    Param(
        [string] $appFilePath,
        [string] $commitMessage,
        [string] $targetBranch = "HEAD:$($ENV:BUILD_SOURCEBRANCH)"
    )

    OutputDebug -Message "Staging changes for $appFilePath"
    invoke-git add $appFilePath

    if ($commitMessage -eq '') {
        $commitMessage = "BCDevOps Flows Update [skip azurepipelines]"
    }
    else {
        $commitMessage = "$commitMessage [skip azurepipelines]"
    }
    OutputDebug -Message "Committing changes for $appFilePath with message: $commitMessage"
    invoke-git commit -m $commitMessage
    OutputDebug -Message "Pushing changes for $appFilePath to $targetBranch"
    invoke-git push origin $targetBranch
}
