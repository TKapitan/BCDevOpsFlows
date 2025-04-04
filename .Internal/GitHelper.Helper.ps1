. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

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
function Invoke-GitAdd {
    Param(
        [string] $appFilePath
    )

    OutputDebug -Message "Staging changes for $appFilePath"
    invoke-git add $appFilePath
}
function Invoke-GitCommit {
    Param(
        [string] $commitMessage
    )

    if ($commitMessage -eq '') {
        $commitMessage = "BCDevOps Flows Update [skip azurepipelines]"
    }
    else {
        $commitMessage = "$commitMessage [skip azurepipelines]"
    }
    OutputDebug -Message "Committing changes with message: $commitMessage"
    invoke-git commit -m $commitMessage
}
function Invoke-GitPush {
    Param(
        [string] $targetBranch = "HEAD:$($ENV:BUILD_SOURCEBRANCH)"
    )

    OutputDebug -Message "Pushing changes to $targetBranch"
    invoke-git push origin $targetBranch
}
function Invoke-GitAddCommit {
    Param(
        [Parameter(Mandatory = $false)]
        [string] $appFilePath,
        [Parameter(Mandatory = $false)]
        [string] $appFolderPath,
        [Parameter(Mandatory = $true)]
        [string] $commitMessage
    )

    if ([string]::IsNullOrEmpty($appFolderPath)) {
        if ([string]::IsNullOrEmpty($appFilePath)) {
            Write-Error "Either appFilePath or appFolderPath must be provided."
        }
        Invoke-GitAdd -appFilePath $appFilePath
    } else {
        Get-ChildItem -Path $appFolderPath -Recurse | ForEach-Object {
            Invoke-GitAdd -appFilePath $_.FullName
        }
        return
    }
    Invoke-GitCommit -commitMessage $commitMessage
}
function Invoke-GitAddCommitPush {
    Param(
        [string] $appFilePath,
        [string] $commitMessage,
        [string] $targetBranch = "HEAD:$($ENV:BUILD_SOURCEBRANCH)"
    )

    Invoke-GitAddCommit -appFilePath $appFilePath -commitMessage $commitMessage
    Invoke-GitPush -targetBranch $targetBranch
}
