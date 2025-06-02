. (Join-Path -Path $PSScriptRoot -ChildPath ".\WriteOutput.Helper.ps1" -Resolve)

function Set-GitUser {
    invoke-git config --global user.email "BCDevOpsFlows@dev.azure.com"
    invoke-git config --global user.name "BCDevOps Flows Pipeline"
    invoke-git config --global core.ignoreCase true
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
            throw "Either appFilePath or appFolderPath must be provided."
        }
        OutputDebug -Message "Restoring unstaged changes for $appFilePath"
        invoke-git restore $appFilePath
    }
    else {
        Get-ChildItem -Path $appFolderPath -Recurse -File | ForEach-Object {
            OutputDebug -Message "Restoring unstaged changes for $($_.FullName)"
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
            throw "Either appFilePath or appFolderPath must be provided."
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

    try {
        invoke-git status --porcelain
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host $_.ScriptStackTrace
        Write-Host $_.PSMessageDetails

        Write-Host "Commit failed. This may be because there are no changes. See previous lines for details."
        return
    }
    Write-Host "Committing changes with message: $commitMessage"
    invoke-git commit -m $commitMessage
}
function Invoke-GitPush {
    Param(
        [Parameter(Mandatory = $false)]
        [string] $targetBranch = "HEAD:$($ENV:BUILD_SOURCEBRANCH)"
    )

    if ($ENV:AL_PIPELINENAME -eq 'SetupPipelines') {
        Invoke-GitPushToAllBranches
        return
    }

    Write-Host "Pushing changes to $targetBranch"
    invoke-git push origin $targetBranch
    if ($targetBranch -match "(HEAD:)?(main|master)$") {
        Invoke-GitPushToTestBranches
    }
}
function Invoke-GitPushToTestBranches {
    param (
        [Parameter(Mandatory = $false)]
        [string[]] $targetBranches = @('test', 'preview')
    )

    Write-Host "Merging changes to $($targetBranches -join ', ')"
    $sourceBranchName = $ENV:BUILD_SOURCEBRANCH.Split(':')[-1]
    if ($sourceBranchName -in $targetBranches) {
        Write-Host "Source branch $sourceBranchName is same as target branch, skipping it..."
        $targetBranches = $targetBranches | Where-Object { $_ -ne $sourceBranchName }
    }

    if ($targetBranches.Count -eq 0) {
        Write-Host "No target branches to merge into, skipping..."
        return
    }
    invoke-git fetch --all
    foreach ($branch in $targetBranches) {
        $branchExists = invoke-git ls-remote --heads origin $branch -returnSuccess
        if ($branchExists) {
            Write-Host "Merging to $branch branch"
            Invoke-GitPush -targetBranch "HEAD:$branch"
            Write-Host "Successfully merged to $branch"
        }
        else {
            OutputDebug -Message "Branch $branch does not exist, skipping..."
        }
    }
    return 0 # override the default exit code from git ls-remote
}
function Invoke-GitPushToAllBranches {
    param ()

    Write-Host "Pushing changes to all branches"
    invoke-git fetch --all

    # Get all remote branches
    $branches = invoke-git branch --remotes | ForEach-Object { $_.Trim() } | Where-Object { 
        $_ -match "^origin/" -and 
        $_ -notmatch "HEAD"
    } | ForEach-Object { $_.Replace("origin/", "") }

    foreach ($branch in $branches) {
        Write-Host "Pushing to $branch branch"
        try {
            invoke-git push origin $branch
            Write-Host "Successfully pushed to $branch"
        }
        catch {
            Write-Host "Failed to push to $($branch): $($_.Exception.Message)" -ForegroundColor Yellow
            continue
        }
    }
    return 0
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
            throw "Either appFilePath or appFolderPath must be provided."
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
