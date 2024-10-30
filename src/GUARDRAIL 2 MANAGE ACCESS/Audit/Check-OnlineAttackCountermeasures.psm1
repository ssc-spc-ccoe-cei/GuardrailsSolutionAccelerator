function Check-OnlineAttackCountermeasures {
    param (
        [string] $ControlName,
        [string] $ItemName,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [string] $CloudUsageProfiles = "3",  # Passed as a string
        [string] $ModuleProfiles,  # Passed as a string
        [switch] $EnableMultiCloudProfiles # New feature flag, default to false
    )

    [bool] $IsCompliant = $true
    [string] $Comments = ""
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    [bool] $LockoutThresholdNonCompliant = $false
    [bool] $BannedPasswordListNonCompliant = $false

    # Fetch group settings
    try {
        $groupSettings = Invoke-GraphQuery -urlPath "/groupSettings" -ErrorAction Stop
        $groupSettingsJsonObject = $groupSettings.Content
        $passwordRuleSettings = $groupSettingsJsonObject.value | Where-Object { $_.displayName -eq "Password Rule Settings" }
        
        if ($null -eq $passwordRuleSettings) {
            throw "Password Rule Settings not found in group settings"
        }
        # Check 1: Lockout Threshold
        $lockoutThreshold = ($passwordRuleSettings.values | Where-Object { $_.name -eq "LockoutThreshold" }).value

        if ([int]$lockoutThreshold -gt 10) {
            $IsCompliant = $false
            $LockoutThresholdNonCompliant = $true
        }

        # Check 2: Banned Password List
        $bannedPasswordListSetting = ($passwordRuleSettings.values | Where-Object { $_.name -eq "BannedPasswordList" }).value
        $bannedPasswords = $bannedPasswordListSetting -split '\t'

        if ($null -eq $bannedPasswords -or $bannedPasswords.Count -eq 0) {
            $IsCompliant = $false
            $BannedPasswordListNonCompliant = $true
        }
        else {
            $requiredBannedPasswords = @("password", "Password!", "Summer2018")
            $missingPasswords = $requiredBannedPasswords | Where-Object { $_ -notin $bannedPasswords }

            if ($missingPasswords.Count -gt 0) {
                $IsCompliant = $false
                $BannedPasswordListNonCompliant = $true
            }
        }
    }
    catch {
        $ErrorList.Add("Failed to retrieve or process group settings: $_")
        $IsCompliant = $false
    }

    if (-not $IsCompliant) {
        if ($LockoutThresholdNonCompliant -and $BannedPasswordListNonCompliant) {
            $Comments = $msgTable.onlineAttackNonCompliantC1C2
        } else {
            if ($LockoutThresholdNonCompliant) {
                $Comments += $msgTable.onlineAttackNonCompliantC1 + " "
            }
            if ($BannedPasswordListNonCompliant) {
                $Comments += $msgTable.onlineAttackNonCompliantC2 + " "
            }
        }
    }
    elseif ($IsCompliant) {
        $Comments = $msgTable.onlineAttackIsCompliant
    }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }

    # Conditionally add the Profile field based on the feature flag
    if ($EnableMultiCloudProfiles) {
        $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
        if (!$evalResult.ShouldEvaluate) {
            Write-Output "No matching profile found"
            $PsObject.ComplianceStatus = "Not Applicable"
        } else {
            Write-Output "Valid profile returned: $($evalResult.Profile)"
            $PsObject | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
        }
    }

    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $PsObject
        Errors            = $ErrorList
    }

    return $moduleOutput
}