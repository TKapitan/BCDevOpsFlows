.(Join-Path -Path $PSScriptRoot -ChildPath "..\BCDevOpsFlows.Setup.ps1" -Resolve)

# Read settings from the settings files
# Settings are read from the following files:
# - BCDevOpsFlowsProjectSettings (Azure DevOps Variable)       = Project settings variable
# - .azure-pipelines/BCDevOpsFlows-Settings.json               = Repository Settings file
# - BCDevOpsFlowsRepoSettings (Azure DevOps Variable)          = Repository settings variable
# - .azure-pipelines/<pipelineName>.settings.json           = Workflow settings file
# - .azure-pipelines/<userReqForEmail>.settings.json        = User settings file
function ReadSettings {
    Param(
        [string] $baseFolder = ("$ENV:PIPELINE_WORKSPACE/App"),
        [string] $repoName = "$ENV:BUILD_REPOSITORY_NAME",
        [string] $buildMode = "Default",
        [string] $pipelineName = "$ENV:BUILD_DEFINITIONNAME",
        [string] $userReqForEmail = "$ENV:BUILD_REQUESTEDFOREMAIL",
        [string] $branchName = "$ENV:BUILD_SOURCEBRANCHNAME",
        [string] $projectSettingsVariableValue = "$ENV:AL_SETTINGS",
        [string] $repoSettingsVariableValue
    )

    # If the build is triggered by a pull request the refname will be the merge branch. To apply conditional settings we need to use the base branch
    if ($ENV:BUILD_REASON -eq "PullRequest") {
        $branchName = $ENV:SYSTEM_PULLREQUEST_SOURCEBRANCH
    }

    function GetSettingsObject {
        Param(
            [string] $path
        )

        if (Test-Path $path) {
            try {
                Write-Host "Applying settings from $path"
                $settings = Get-Content $path -Encoding UTF8 | ConvertFrom-Json
                if ($settings) {
                    return $settings
                }
            }
            catch {
                Write-Error "Error reading $path. Error was $($_.Exception.Message).`n$($_.ScriptStackTrace)"
            }
        }
        else {
            Write-Host "No settings found in $path"
        }
        return $null
    }

    $repoName = $repoName.SubString("$repoName".LastIndexOf('/') + 1)
    $pipelineName = $pipelineName.Trim().Split([System.IO.Path]::getInvalidFileNameChars()) -join ""

    # Start with default settings
    $settings = [ordered]@{
        "type"                                          = "PTE"
        "country"                                       = "au"
        "artifact"                                      = ""
        "companyName"                                   = ""
        "repoVersion"                                   = "1.0"
        "repoName"                                      = $repoName
        "versioningStrategy"                            = 0
        "runNumberOffset"                               = 0
        "appBuild"                                      = 0
        "appRevision"                                   = 0
        "keyVaultName"                                  = ""
        "licenseFileUrlSecretName"                      = "licenseFileUrl"
        "adminCenterApiCredentialsSecretName"           = "adminCenterApiCredentials"
        "applicationInsightsConnectionStringSecretName" = "applicationInsightsConnectionString"
        "keyVaultCertificateUrlSecretName"              = ""
        "keyVaultCertificatePasswordSecretName"         = ""
        "keyVaultClientIdSecretName"                    = ""
        "keyVaultCodesignCertificateName"               = ""
        "codeSignCertificateUrlSecretName"              = "codeSignCertificateUrl"
        "codeSignCertificatePasswordSecretName"         = "codeSignCertificatePassword"
        "additionalCountries"                           = @()
        "appDependencies"                               = @()
        "appFolders"                                    = @()
        "testDependencies"                              = @()
        "testFolders"                                   = @()
        "bcptTestFolders"                               = @()
        "pageScriptingTests"                            = @()
        "restoreDatabases"                              = @()
        "installApps"                                   = @()
        "installTestApps"                               = @()
        "installOnlyReferencedApps"                     = $true
        "generateDependencyArtifact"                    = $false
        "skipUpgrade"                                   = $false
        "applicationDependency"                         = "25.0.0.0"
        "updateDependencies"                            = $false
        "installTestRunner"                             = $false
        "installTestFramework"                          = $false
        "installTestLibraries"                          = $false
        "installPerformanceToolkit"                     = $false
        "enableCodeCop"                                 = $false
        "enableUICop"                                   = $false
        "enableCodeAnalyzersOnTestApps"                 = $false
        "customCodeCops"                                = @()
        "failOn"                                        = "error"
        "treatTestFailuresAsWarnings"                   = $false
        "rulesetFile"                                   = ""
        "enableExternalRulesets"                        = $false
        "vsixFile"                                      = ""
        "assignPremiumPlan"                             = $false
        "enableTaskScheduler"                           = $false
        "doNotBuildTests"                               = $false
        "doNotRunTests"                                 = $false
        "doNotRunBcptTests"                             = $false
        "doNotRunPageScriptingTests"                    = $false
        "doNotPublishApps"                              = $false
        "doNotSignApps"                                 = $false
        "configPackages"                                = @()
        "appSourceCopMandatoryAffixes"                  = @()
        "obsoleteTagMinAllowedMajorMinor"               = ""
        "memoryLimit"                                   = ""
        "templateUrl"                                   = ""
        "templateSha"                                   = ""
        "templateBranch"                                = ""
        "appDependencyProbingPaths"                     = @()
        "useProjectDependencies"                        = $false
        "buildRunner"                                   = "windows-latest"
        "buildRunnerShell"                              = ""
        "cacheImageName"                                = "my"
        "cacheKeepDays"                                 = 3
        "environments"                                  = @()
        "buildModes"                                    = @()
        "useCompilerFolder"                             = $false
        "pullRequestTrigger"                            = "pull_request_target"
        "bcptThresholds"                                = [ordered]@{
            "DurationWarning"         = 10
            "DurationError"           = 25
            "NumberOfSqlStmtsWarning" = 5
            "NumberOfSqlStmtsError"   = 10
        }
        "fullBuildPatterns"                             = @()
        "excludeEnvironments"                           = @()
        "commitOptions"                                 = [ordered]@{
            "messageSuffix"        = ""
            "pullRequestAutoMerge" = $false
            "pullRequestLabels"    = @()
        }
        "trustedSigning"                                = [ordered]@{
            "Endpoint"           = ""
            "Account"            = ""
            "CertificateProfile" = ""
        }
        "useGitSubmodules"                              = "false"
        "gitSubmodulesTokenSecretName"                  = "gitSubmodulesToken"
    }

    # Read settings from files and merge them into the settings object

    $settingsObjects = @()
    # Read settings from project settings variable (parameter)
    if ($projectSettingsVariableValue) {
        $projectSettingsVariableValueObject = $projectSettingsVariableValue | ConvertFrom-Json
        $settingsObjects += @($projectSettingsVariableValueObject)
    }
    # Read settings from repository settings file
    $repoSettingsObject = GetSettingsObject -Path (Join-Path $baseFolder $RepoSettingsFile)
    $settingsObjects += @($repoSettingsObject)
    # Read settings from repository settings variable (parameter)
    if ($repoSettingsVariableValue) {
        $repoSettingsVariableObject = $repoSettingsVariableValue | ConvertFrom-Json
        $settingsObjects += @($repoSettingsVariableObject)
    }
    if ($pipelineName) {
        # Read settings from workflow settings file
        $workflowSettingsObject = GetSettingsObject -Path (Join-Path $baseFolder "$scriptsFolderName/$pipelineName.settings.json")
        $settingsObjects += @($workflowSettingsObject)
        # Read settings from user settings file
        $userSettingsObject = GetSettingsObject -Path (Join-Path $baseFolder "$scriptsFolderName/$userReqForEmail.settings.json")
        $settingsObjects += @($userSettingsObject)
    }
    $BCDevOpsFlowsSettingExists = $false
    foreach ($settingsJson in $settingsObjects) {
        if ($settingsJson) {
            MergeCustomObjectIntoOrderedDictionary -dst $settings -src $settingsJson
            if ($settingsJson.PSObject.Properties.Name -eq "ConditionalSettings") {
                foreach ($conditionalSetting in $settingsJson.ConditionalSettings) {
                    if ("$conditionalSetting" -ne "") {
                        $conditionMet = $true
                        $conditions = @()
                        if ($conditionalSetting.PSObject.Properties.Name -eq "buildModes") {
                            $conditionMet = $conditionMet -and ($conditionalSetting.buildModes | Where-Object { $buildMode -like $_ })
                            $conditions += @("buildMode: $buildMode")
                        }
                        if ($conditionalSetting.PSObject.Properties.Name -eq "branches") {
                            $conditionMet = $conditionMet -and ($conditionalSetting.branches | Where-Object { $branchName -like $_ })
                            $conditions += @("branchName: $branchName")
                        }
                        if ($conditionalSetting.PSObject.Properties.Name -eq "repositories") {
                            $conditionMet = $conditionMet -and ($conditionalSetting.repositories | Where-Object { $repoName -like $_ })
                            $conditions += @("repoName: $repoName")
                        }
                        if ($pipelineName -and $conditionalSetting.PSObject.Properties.Name -eq "workflows") {
                            $conditionMet = $conditionMet -and ($conditionalSetting.workflows | Where-Object { $pipelineName -like $_ })
                            $conditions += @("pipelineName: $pipelineName")
                        }
                        if ($userReqForEmail -and $conditionalSetting.PSObject.Properties.Name -eq "users") {
                            $conditionMet = $conditionMet -and ($conditionalSetting.users | Where-Object { $userReqForEmail -like $_ })
                            $conditions += @("userReqForEmail: $userReqForEmail")
                        }
                        if ($conditionMet) {
                            Write-Host "Applying conditional settings for $($conditions -join ", ")"
                            MergeCustomObjectIntoOrderedDictionary -dst $settings -src $conditionalSetting.settings
                        }
                    }
                }
            }
            $BCDevOpsFlowsSettingExists = $true
        }
    }

    if ($BCDevOpsFlowsSettingExists -eq $false) {
        Write-Error "No BCDevOpsFlows settings found. Please check that the repository is correctly configured and follows BCDevOpsFlows rules."
    }
    if ($settings.buildRunner -eq "") {
        $settings.buildRunner = "windows-latest"
    }
    if ($settings.buildRunnerShell -eq "") {
        $settings.buildRunnerShell = "powershell"
    }
    # Check that buildRunnerShell and Shell is valid
    if ($settings.buildRunnerShell -ne "powershell" -and $settings.buildRunnerShell -ne "pwsh") {
        Write-Error "Invalid value for setting: buildRunnerShell: $($settings.buildRunnerShell)"
    }
    $settings
}

function MergeCustomObjectIntoOrderedDictionary {
    Param(
        [System.Collections.Specialized.OrderedDictionary] $dst,
        [PSCustomObject] $src
    )

    # Loop through all properties in the source object
    # If the property does not exist in the destination object, add it with the right type, but no value
    # Types supported: PSCustomObject, Object[] and simple types
    $src.PSObject.Properties.GetEnumerator() | ForEach-Object {
        $prop = $_.Name
        $srcProp = $src."$prop"
        $srcPropType = $srcProp.GetType().Name
        if (-not $dst.Contains($prop)) {
            if ($srcPropType -eq "PSCustomObject") {
                $dst.Add("$prop", [ordered]@{})
            }
            elseif ($srcPropType -eq "Object[]") {
                $dst.Add("$prop", @())
            }
            else {
                $dst.Add("$prop", $srcProp)
            }
        }
    }

    # Loop through all properties in the destination object
    # If the property does not exist in the source object, do nothing
    # If the property exists in the source object, but is of a different type, Write-Error an error
    # If the property exists in the source object:
    # If the property is an Object, call this function recursively to merge values
    # If the property is an Object[], merge the arrays
    # If the property is a simple type, replace the value in the destination object with the value from the source object
    @($dst.Keys) | ForEach-Object {
        $prop = $_
        if ($src.PSObject.Properties.Name -eq $prop) {
            $dstProp = $dst."$prop"
            $srcProp = $src."$prop"
            $dstPropType = $dstProp.GetType().Name
            $srcPropType = $srcProp.GetType().Name
            if ($srcPropType -eq "PSCustomObject" -and $dstPropType -eq "OrderedDictionary") {
                MergeCustomObjectIntoOrderedDictionary -dst $dst."$prop" -src $srcProp
            }
            elseif ($dstPropType -ne $srcPropType -and !($srcPropType -eq "Int64" -and $dstPropType -eq "Int32")) {
                # Under Linux, the Int fields read from the .json file will be Int64, while the settings defaults will be Int32
                # This is not seen as an error and will not Write-Error an error
                Write-Error "property $prop should be of type $dstPropType, is $srcPropType."
            }
            else {
                if ($srcProp -is [Object[]]) {
                    $srcProp | ForEach-Object {
                        $srcElm = $_
                        $srcElmType = $srcElm.GetType().Name
                        if ($srcElmType -eq "PSCustomObject") {
                            # Array of objects are not checked for uniqueness
                            $ht = [ordered]@{}
                            $srcElm.PSObject.Properties | Sort-Object -Property Name -Culture "iv-iv" | ForEach-Object {
                                $ht[$_.Name] = $_.Value
                            }
                            $dst."$prop" += @($ht)
                        }
                        else {
                            # Add source element to destination array, but only if it does not already exist
                            $dst."$prop" = @($dst."$prop" + $srcElm | Select-Object -Unique)
                        }
                    }
                }
                else {
                    $dst."$prop" = $srcProp
                }
            }
        }
    }
}