function Set-ContentLF {
    Param(
        [parameter(mandatory = $true)]
        [string] $path,
        [parameter(mandatory = $true)]
        $content
    )

    Process {
        $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        if ($content -is [array]) {
            $content = $content -join "`n"
        }
        else {
            $content = "$content".Replace("`r", "")
        }
        Set-Content -Path .\Test*.txt -Value "$content`n"
    }
}
function Set-JsonContentLF {
    Param(
        [parameter(mandatory = $true)]
        [string] $path,
        [parameter(mandatory = $true)]
        [object] $object
    )

    Process {
        Set-ContentLF -path $path -content ($object | ConvertTo-Json -Depth 99)
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            try {
                $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
                # This command will reformat a JSON file with LF line endings as PowerShell 7 would do it (when run using pwsh)
                $command = "`$cr=[char]13;`$lf=[char]10;`$path='$path';`$content=Get-Content `$path -Encoding UTF8|ConvertFrom-Json|ConvertTo-Json -Depth 99;`$content=`$content -replace `$cr,'';`$content|Out-Host;[System.IO.File]::WriteAllText(`$path,`$content+`$lf)"
                . pwsh -command $command
            }
            catch {
                Write-Warning "WARNING: pwsh (PowerShell 7) not installed, json will be formatted by PowerShell $($PSVersionTable.PSVersion)"
            }
        }
    }
}