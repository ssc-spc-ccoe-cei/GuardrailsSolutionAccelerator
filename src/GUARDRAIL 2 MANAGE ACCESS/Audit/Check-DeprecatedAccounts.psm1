function Check-DeprecatedUsers {
    Param (
        
        [string] $token, 
        [string] $ControlName, 
        [string] $ItemName, 
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [int[]] 
        $moduleProfile,  # New parameter for module profiles
        [int[]] $cloudUsageProfile = @(),  # New parameter for cloud usage profiles, default to empty array
        [bool] 
        $enableMultiCloudProfiles = $false  # New feature flag, default to false

    )
    [bool] $IsCompliant = $false
    [string] $UComments = $msgTable.noncompliantUsers
    [string] $CComments = $msgTable.compliantComment

    [PSCustomObject] $DeprecatedUsers = New-Object System.Collections.ArrayList
    [PSCustomObject] $ErrorList = New-Object System.Collections.ArrayList
    
    # A Deprecated account is an account that is disabled and not synchronized to AD
    $DeprecatedUsers = Get-AzADUser -Filter "accountEnabled eq false" -Select OnPremisesSyncEnabled,UserPrincipalName | Where-Object {$null -eq $_.onPremisesSyncEnabled}

    if ($DeprecatedUsers.count -gt 0) {
        foreach ($user in $DeprecatedUsers) {
            $UComments =  $UComments + $user.userPrincipalName + "  "
        }
        $Comments = $msgTable.noncompliantComment -f $DeprecatedUsers.count +" "+ $UComments
        $MitigationCommands = $msgTable.mitigationCommands 
    }
    else {
        $Comments = $CComments
        $IsCompliant = $true
        $MitigationCommands = "N/A"
    }

    $DeprecatedUserStatus = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        MitigationCommands = $MitigationCommands
        ReportTime = $ReportTime
        itsgcode = $itsgcode
    }

    # Conditionally add the Profile field based on the feature flag
    if ($enableMultiCloudProfiles) {
        $evaluationProfile = Get-EvaluationProfile -CloudUsageProfile $cloudUsageProfile -SubscriptionId (Get-AzContext).Subscription.Id
        $DeprecatedUserStatus | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evaluationProfile
    }

    $moduleOutput= [PSCustomObject]@{ 
        ComplianceResults = $DeprecatedUserStatus
        Errors=$ErrorList
        AdditionalResults = $AdditionalResults
    }
    return $moduleOutput  
    <#
    $JasonDeprecatedUserStatus = ConvertTo-Json -inputObject $DeprecatedUserStatus
        
    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID -sharedkey $workspaceKey `
        -body $JasonDeprecatedUserStatus   -logType $LogType -TimeStampField Get-Date  
    #>
}
       

