function Get-PreprocessorSymbols {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$settings,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$appJsonContent
    )

    $existingSymbols = @{}
    if ($ENV:AL_APPJSONARTIFACT -and $appJsonContent.PSObject.Properties.Name -contains 'preprocessorSymbols') {
        OutputDebug -Message "Adding Preprocessor symbols from app.json: $($appJsonContent.preprocessorSymbols -join ',')"
        $appJsonContent.preprocessorSymbols | Where-Object { $_ } | ForEach-Object { $existingSymbols[$_] = $true }
    }
    if ($settings.ContainsKey('preprocessorSymbols')) {
        OutputDebug -Message "Adding Preprocessor symbols : $($settings.preprocessorSymbols -join ',')"
        $settings.preprocessorSymbols | Where-Object { $_ } | ForEach-Object { $existingSymbols[$_] = $true }
    }
    return $existingSymbols
}
