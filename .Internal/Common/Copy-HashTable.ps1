function Copy-HashTable() {
    [CmdletBinding()]
    [OutputType([System.Collections.HashTable])]
    Param(
        [parameter(ValueFromPipeline)]
        [hashtable] $object
    )
    Process {
        $ht = @{}
        if ($object) {
            $object.Keys | ForEach-Object {
                $ht[$_] = $object[$_]
            }
        }
        $ht
    }
}