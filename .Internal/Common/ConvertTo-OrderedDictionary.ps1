<#
 .Synopsis
  Convert PSCustomObject to OrderedDictionary
 .Description
  Convert PSCustomObject to OrderedDictionary
 .Example
  Get-Content "test.json" | ConvertFrom-Json | ConvertTo-HashTable
#>
function ConvertTo-OrderedDictionary() {
    [CmdletBinding()]
    Param(
        [parameter(ValueFromPipeline)]
        [PSCustomObject] $object,
        [switch] $sort
    )
    $ht = [ordered]@{}
    if ($object) {
        if ($sort) {
            $object.PSObject.Properties | Sort-Object -Property Name -Culture "iv-iv" | ForEach-Object { 
                $ht[$_.Name] = $_.Value 
            }
        }
        else {
            $object.PSObject.Properties | ForEach-Object {
                $ht[$_.Name] = $_.Value
            }
        }
    }
    $ht
}
