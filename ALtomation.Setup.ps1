
$scriptsFolderName = '.azure-pipelines'
$repoSettingsFile = Join-Path '.azure-pipelines' 'ALtomation-Settings.json'
$defaultBcContainerHelperVersion = "preview"

Write-Host "Reading base file structure settings..."
Write-Host " - scriptsFolderName = $scriptsFolderName"
Write-Host " - repoSettingsFile = $repoSettingsFile"
Write-Host " - defaultBcContainerHelperVersion = $defaultBcContainerHelperVersion"

$runAlPipelineOverrides = @(
    "DockerPull"
    "NewBcContainer"
    "ImportTestToolkitToBcContainer"
    "CompileAppInBcContainer"
    "GetBcContainerAppInfo"
    "PublishBcContainerApp"
    "UnPublishBcContainerApp"
    "InstallBcAppFromAppSource"
    "SignBcContainerApp"
    "ImportTestDataInBcContainer"
    "RunTestsInBcContainer"
    "GetBcContainerAppRuntimePackage"
    "RemoveBcContainer"
    "InstallMissingDependencies"
    "PreCompileApp"
    "PostCompileApp"
)

Write-Host "Reading run AL pipeline overrides..."
Write-Host " - runAlPipelineOverrides = $runAlPipelineOverrides"

# Well known AppIds
$systemAppId = "63ca2fa4-4f03-4f2b-a480-172fef340d3f"
$baseAppId = "437dbf0e-84ff-417a-965d-ed2bb9650972"
$applicationAppId = "c1335042-3002-4257-bf8a-75c898ccb1b8"
$permissionsMockAppId = "40860557-a18d-42ad-aecb-22b7dd80dc80"
$testRunnerAppId = "23de40a6-dfe8-4f80-80db-d70f83ce8caf"
$anyAppId = "e7320ebb-08b3-4406-b1ec-b4927d3e280b"
$libraryAssertAppId = "dd0be2ea-f733-4d65-bb34-a28f4624fb14"
$libraryVariableStorageAppId = "5095f467-0a01-4b99-99d1-9ff1237d286f"
$systemApplicationTestLibraryAppId = "9856ae4f-d1a7-46ef-89bb-6ef056398228"
$TestsTestLibrariesAppId = "5d86850b-0d76-4eca-bd7b-951ad998e997"
$performanceToolkitAppId = "75f1590f-55c5-4501-ae63-bada5534e852"

Write-Host "Reading well known AppIds..."
Write-Host " - systemAppId = $systemAppId"
Write-Host " - baseAppId = $baseAppId"
Write-Host " - applicationAppId = $applicationAppId"
Write-Host " - permissionsMockAppId = $permissionsMockAppId"
Write-Host " - testRunnerAppId = $testRunnerAppId"
Write-Host " - anyAppId = $anyAppId"
Write-Host " - libraryAssertAppId = $libraryAssertAppId"
Write-Host " - libraryVariableStorageAppId = $libraryVariableStorageAppId"
Write-Host " - systemApplicationTestLibraryAppId = $systemApplicationTestLibraryAppId"
Write-Host " - TestsTestLibrariesAppId = $TestsTestLibrariesAppId"
Write-Host " - performanceToolkitAppId = $performanceToolkitAppId"

$performanceToolkitApps = @($performanceToolkitAppId)
$testLibrariesApps = @($systemApplicationTestLibraryAppId, $TestsTestLibrariesAppId)
$testFrameworkApps = @($anyAppId, $libraryAssertAppId, $libraryVariableStorageAppId) + $testLibrariesApps
$testRunnerApps = @($permissionsMockAppId, $testRunnerAppId) + $performanceToolkitApps + $testLibrariesApps + $testFrameworkApps

Write-Host "Reading well known AppIds collections..."
Write-Host " - performanceToolkitApps = $performanceToolkitApps"
Write-Host " - testLibrariesApps = $testLibrariesApps"
Write-Host " - testFrameworkApps = $testFrameworkApps"
Write-Host " - testRunnerApps = $testRunnerApps"

. (Join-Path -Path $PSScriptRoot -ChildPath "Troubleshooting\Troubleshooting.Helper.ps1" -Resolve)