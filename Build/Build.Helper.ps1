function Get-PreprocessorSymbols {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$settings,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$appJsonContent
    )

    $existingSymbols = @{}
    
    # Add preprocessor symbols from app.json
    if ($appJsonContent -and ($appJsonContent.PSObject.Properties.Name -contains 'preprocessorSymbols')) {
        OutputDebug -Message "Adding Preprocessor symbols from app.json: $($appJsonContent.preprocessorSymbols -join ',')"
        $appJsonContent.preprocessorSymbols | Where-Object { $_ } | ForEach-Object { 
            $existingSymbols[$_.Trim()] = $true 
        }
    }
    
    # Add preprocessor symbols from settings
    if ($settings.ContainsKey('preprocessorSymbols')) {
        OutputDebug -Message "Adding Preprocessor symbols: $($settings.preprocessorSymbols -join ',')"
        $settings.preprocessorSymbols | Where-Object { $_ } | ForEach-Object { 
            $existingSymbols[$_.Trim()] = $true 
        }
    }
    
    # Remove ignored preprocessor symbols
    if ($settings.ContainsKey('ignoredPreprocessorSymbols')) {
        OutputDebug -Message "Removing ignored Preprocessor symbols: $($settings.ignoredPreprocessorSymbols -join ',')"
        $settings.ignoredPreprocessorSymbols | Where-Object { $_ } | ForEach-Object { 
            $existingSymbols.Remove($_.Trim()) | Out-Null
        }
    }
    
    # Add country preprocessor symbols if enabled
    if (($settings.ContainsKey('generateCountryPreprocessorSymbols')) -and $settings.generateCountryPreprocessorSymbols) {
        # Remove any existing COUNTRY_XX symbols from app.json
        $countrySymbolsToRemove = $existingSymbols.Keys | Where-Object { $_ -match '^COUNTRY_[A-Z0-9]+$' }
        $countrySymbolsToRemove | ForEach-Object {
            OutputDebug -Message "Removing existing country preprocessor symbol from app.json: $_"
            $existingSymbols.Remove($_) | Out-Null
        }
        
        $countryCodes = @()
        
        # Add primary country
        if (($settings.ContainsKey('country')) -and $settings.country) {
            if ($settings.country -is [array]) {
                $countryCodes += $settings.country
            } else {
                $countryCodes += ($settings.country -split '[,;\s]+' | Where-Object { $_.Trim() -ne '' })
            }
        }
        
        # Add additional countries
        if (($settings.ContainsKey('additionalCountries')) -and $settings.additionalCountries) {
            if ($settings.additionalCountries -is [array]) {
                $countryCodes += $settings.additionalCountries
            } else {
                $countryCodes += ($settings.additionalCountries -split '[,;\s]+' | Where-Object { $_.Trim() -ne '' })
            }
        }
        
        # Generate country symbols
        $countryCodes | Where-Object { $_.Trim() -ne '' } | ForEach-Object { 
            $countrySymbol = "COUNTRY_$($_.Trim().ToUpper())"
            OutputDebug -Message "Adding country preprocessor symbol: $countrySymbol"
            $existingSymbols[$countrySymbol] = $true
        }
    }
    return $existingSymbols
}
