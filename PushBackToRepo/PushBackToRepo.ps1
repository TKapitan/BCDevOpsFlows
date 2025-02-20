. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\GitHelper.Helper.ps1" -Resolve)

# Push commited changes to DevOps
Invoke-GitPush