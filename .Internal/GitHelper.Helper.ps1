. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\WriteOutput.Helper.ps1" -Resolve)

function Set-GitUser {
    invoke-git config --global user.email "BCDevOpsFlows@dev.azure.com"
    invoke-git config --global user.name "BCDevOps Flows Pipeline"
}
function Invoke-RestoreUnstagedChanges {
    Param(
        [Parameter(Mandatory = $false)]
        [string] $appFilePath,
        [Parameter(Mandatory = $false)]
        [string] $appFolderPath
    )

    if ([string]::IsNullOrEmpty($appFolderPath)) {
        if ([string]::IsNullOrEmpty($appFilePath)) {
            Write-Error "Either appFilePath or appFolderPath must be provided."
        }
        OutputDebug -Message "Restoring unstaged changes for $appFilePath"
        invoke-git restore $appFilePath
    }
    else {
        Get-ChildItem -Path $appFolderPath -Recurse | ForEach-Object {
            OutputDebug -Message "Restoring unstaged changes for $($_.FullName))"
            invoke-git restore $_.FullName
        }
    }
}
function Invoke-GitAdd {
    Param(
        [Parameter(Mandatory = $false)]
        [string] $appFilePath,
        [Parameter(Mandatory = $false)]
        [string] $appFolderPath
    )

    if ([string]::IsNullOrEmpty($appFolderPath)) {
        if ([string]::IsNullOrEmpty($appFilePath)) {
            Write-Error "Either appFilePath or appFolderPath must be provided."
        }
        OutputDebug -Message "Staging changes for $appFilePath"
        invoke-git add $appFilePath
    }
    else {
        Get-ChildItem -Path $appFolderPath -Recurse | ForEach-Object {
            OutputDebug -Message "Staging changes for $($_.FullName)"
            invoke-git add $_.FullName
        }
    }
}
function Invoke-GitCommit {
    Param(
        [Parameter(Mandatory = $false)]
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
        [Parameter(Mandatory = $false)]
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
        [Parameter(Mandatory = $false)]
        [string] $commitMessage
    )

    if ([string]::IsNullOrEmpty($appFolderPath)) {
        if ([string]::IsNullOrEmpty($appFilePath)) {
            Write-Error "Either appFilePath or appFolderPath must be provided."
        }
        Invoke-GitAdd -appFilePath $appFilePath
    }
    else {
        Invoke-GitAdd -appFolderPath $appFolderPath
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
