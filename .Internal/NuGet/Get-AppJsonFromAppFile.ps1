<# 
 .Synopsis
  Extract the app.json file from an app (also from runtime packages)
 .Description
 .Parameter AppFile
  Path of the application file from which to extract the app.json
 .Example
  Get-AppJsonFromAppFile -appFile c:\temp\baseapp.app
#>
function Get-AppJsonFromAppFile {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $appFile
    )

    function RunAlTool {
        Param(
            [string[]] $arguments
        )

        try {
            $ALToolExeLocation = Join-Path $ENV:AL_BCDEVTOOLSFOLDER 'altool.exe'
            CmdDo -Command $ALToolExeLocation -arguments $arguments -returnValue -silent
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host $_.ScriptStackTrace
            Write-Host $_.PSMessageDetails
    
            throw "Unable to run AlTool. Make sure that the BCDevTools are available and compatible with the current version."
        }
    }

    $appJson = RunAlTool -arguments @('GetPackageManifest', """$appFile""") | ConvertFrom-Json
    if (!($appJson.PSObject.Properties.Name -eq "description")) { Add-Member -InputObject $appJson -MemberType NoteProperty -Name "description" -Value "" }
    if (!($appJson.PSObject.Properties.Name -eq "dependencies")) { Add-Member -InputObject $appJson -MemberType NoteProperty -Name "dependencies" -Value @() }
    return $appJson
}