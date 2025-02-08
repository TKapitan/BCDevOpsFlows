. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Internal\Nuget.Helper.ps1" -Resolve)

function InstallAndRegisterNugetPackageProvider() {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -Force
    AddNugetPackageSource -sourceName 'nuget.org' -sourceUrl 'https://api.nuget.org/v3/index.json'
}
