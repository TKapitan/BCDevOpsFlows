# Copy of NuGet class from BCContainerHelper, required changed to support Azure DevOps preview packages

<# 
 .Synopsis
  PROOF OF CONCEPT PREVIEW: Push Business Central NuGet Package to NuGet Server
 .Description
  Push Business Central NuGet Package to NuGet Server
 .PARAMETER nuGetServerUrl
  NuGet Server URL
 .PARAMETER nuGetToken
  NuGet Token for authenticated access to the NuGet Server
 .PARAMETER bcNuGetPackage
  Path to BcNuGetPackage to push. This is the value returned by New-BCDevOpsFlowsNuGetPackage.
 .EXAMPLE
  $package = New-BCDevOpsFlowsNuGetPackage -appfile $appFileName
  Push-BCDevOpsFlowsNuGetPackage -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken -bcNuGetPackage $package
#>
Function Push-BCDevOpsFlowsNuGetPackage {
    Param(
        [Parameter(Mandatory=$true)]
        [string] $nuGetServerUrl,
        [Parameter(Mandatory=$true)]
        [string] $nuGetToken,
        [Parameter(Mandatory=$true)]
        [string] $bcNuGetPackage
    )

    $nuGetFeed = [BcDevOpsFlowsNuGetFeed]::Create($nuGetServerUrl, $nuGetToken, @(), @())
    $nuGetFeed.PushPackage($bcNuGetPackage)
}
Export-ModuleMember -Function Push-BCDevOpsFlowsNuGetPackage