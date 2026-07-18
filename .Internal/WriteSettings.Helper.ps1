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
        # Write UTF-8 without BOM with an exact trailing LF on both PowerShell editions
        # (Set-Content would use the ANSI code page on Windows PowerShell 5.1)
        [System.IO.File]::WriteAllText($path, "$content`n", [System.Text.UTF8Encoding]::new($false))
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
                Write-Host "Formatting JSON file with LF line endings using pwsh as PowerShell 7 would do it"
                $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
                # This command will reformat a JSON file with LF line endings as PowerShell 7 would do it (when run using pwsh)
                $command = "`$cr=[char]13;`$lf=[char]10;`$path='$path';`$content=Get-Content `$path -Encoding UTF8|ConvertFrom-Json|ConvertTo-Json -Depth 99;`$content=`$content -replace `$cr,'';[System.IO.File]::WriteAllText(`$path,`$content+`$lf)"
                . pwsh -command $command
            }
            catch {
                Write-Warning "WARNING: pwsh (PowerShell 7) not installed, json will be formatted by PowerShell $($PSVersionTable.PSVersion)"
            }
        }
    }
}