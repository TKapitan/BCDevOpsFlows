. (Join-Path -Path $PSScriptRoot -ChildPath ".\WriteOutput.Helper.ps1" -Resolve)

<# 
 .Synopsis
  Invoke git command with parameters
 .Description
  Requires Git installed  
#>
function invoke-git {
    Param(
        [parameter(mandatory = $false, ValueFromPipeline = $true)]
        [string] $inputStr = "",
        [switch] $silent,
        [switch] $returnValue,
        [switch] $returnSuccess,
        [parameter(mandatory = $true, position = 0)]
        [string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] 
        $remaining
    )

    Process {
        $arguments = "$command "
        foreach ($parameter in $remaining) {
            if ("$parameter".IndexOf(" ") -ge 0 -or "$parameter".IndexOf('"') -ge 0) {
                $arguments += """$($parameter.Replace('"','\"'))"" "
            }
            else {
                $arguments += "$parameter "
            }
        }
        if ($returnSuccess) {
            $cmdDoResults = cmdDo -command git -arguments $arguments -silent:$silent -returnValue:$returnValue -returnSuccess -inputStr $inputStr -messageIfCmdNotFound "Git not found. Please install it from https://git-scm.com/downloads"
            OutputDebug -Message "CmdDo results: $cmdDoResults"
            return $cmdDoResults
        }
        cmdDo -command git -arguments $arguments -silent:$silent -returnValue:$returnValue -inputStr $inputStr -messageIfCmdNotFound "Git not found. Please install it from https://git-scm.com/downloads"
    }
}