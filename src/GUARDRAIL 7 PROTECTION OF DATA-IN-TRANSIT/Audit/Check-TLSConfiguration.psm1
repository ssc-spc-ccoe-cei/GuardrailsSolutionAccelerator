function Verify-TLSConfiguration {
    param (
        [string] $ControlName,
        [string] $ItemName,
        [string] $itsgcode,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string] $ReportTime,
        [string] $ModuleProfiles,
        [string] $CloudUsageProfiles = "3",
        [switch] $EnableMultiCloudProfiles
    )

    $ObjectList = New-Object System.Collections.ArrayList
    $ErrorList = New-Object System.Collections.ArrayList


    # Define required policies based on ItemName
    $grRequiredPolicies = @()
    
    switch ($ItemName) {
        "App Service TLS Configuration" {
            $grRequiredPolicies = @(
                "/providers/Microsoft.Authorization/policyDefinitions/f0e6e85b-9b9f-4a4b-b67b-f730d42f1b0b",
                "/providers/Microsoft.Authorization/policyDefinitions/817dcf37-e83d-4999-a472-644eada2ea1e",
                "/providers/Microsoft.Authorization/policyDefinitions/d6545c6b-dd9d-4265-91e6-0b451e2f1c50"
            )
        }
        "Function App TLS Configuration" {
            $grRequiredPolicies = @(
                "/providers/Microsoft.Authorization/policyDefinitions/fa3a6357-c6d6-4120-8429-855577ec0063",
                "/providers/Microsoft.Authorization/policyDefinitions/1f01f1c7-539c-49b5-9ef4-d4ffa37d22e0"
            )
        }
        "Azure SQL Database TLS Configuration" {
            $grRequiredPolicies = @(
                "/providers/Microsoft.Authorization/policyDefinitions/32e6bbec-16b6-44c2-be37-c5b672d103cf"
            )
        }
        "Application Gateway WAF TLS Configuration" {
            $grRequiredPolicies = @(
                "/providers/Microsoft.Authorization/policyDefinitions/564feb30-bf6a-4854-b4bb-0d2d2d1e6c66"
            )
        }
    }

    if ($EnableMultiCloudProfiles) {
        $ObjectList += Check-BuiltInPolicies -requiredPolicyIds $grRequiredPolicies -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -itsgcode $itsgcode -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles -EnableMultiCloudProfiles -ErrorList $ErrorList
    } else {
        $ObjectList += Check-BuiltInPolicies -requiredPolicyIds $grRequiredPolicies -ReportTime $ReportTime -ItemName $ItemName -msgTable $msgTable -ControlName $ControlName -itsgcode $itsgcode -ErrorList $ErrorList
    }

    Write-Output "Policy compliance results are collected"
    
    # Filter out PSAzureContext objects
    $ObjectList_filtered = $ObjectList | Where-Object { $_.GetType() -notlike "*PSAzureContext*" }

    $moduleOutput = [PSCustomObject]@{
        ComplianceResults = $ObjectList_filtered
        Errors = $ErrorList
    }
    
    return $moduleOutput
}

# function Check-BuiltInPolicies {
#     param (
#         [Parameter(Mandatory=$true)]
#         [array]$requiredPolicyIds,
#         [Parameter(Mandatory=$true)]
#         [string]$ReportTime,
#         [Parameter(Mandatory=$true)]
#         [string]$ItemName,
#         [Parameter(Mandatory=$true)]
#         [hashtable]$msgTable,
#         [Parameter(Mandatory=$true)]
#         [string]$ControlName,
#         [string]$itsgcode,
#         [string]$CloudUsageProfiles = "3",
#         [string]$ModuleProfiles,
#         [switch]$EnableMultiCloudProfiles,
#         [System.Collections.ArrayList]$ErrorList
#     )

#     function Add-ProfileInformation {
#         param (
#             [Parameter(Mandatory=$true)]
#             [PSCustomObject]$Result,
#             [string]$CloudUsageProfiles,
#             [string]$ModuleProfiles
#         )
        
#         $evalResult = Get-EvaluationProfile -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
#         if (!$evalResult.ShouldEvaluate) {
#             if ($evalResult.Profile -gt 0) {
#                 $Result.ComplianceStatus = "Not Applicable"
#                 $Result | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
#                 $Result.Comments = "Not evaluated - Profile $($evalResult.Profile) not present in CloudUsageProfiles"
#             }
#         } else {
#             $Result | Add-Member -MemberType NoteProperty -Name "Profile" -Value $evalResult.Profile
#         }
#         return $Result
#     }

#     $results = New-Object System.Collections.ArrayList
    
#     # Get tenant root management group
#     try {
#         $tenantId = (Get-AzContext).Tenant.Id
#         $rootScope = "/providers/Microsoft.Management/managementGroups/$tenantId"
#     } catch {
#         $ErrorList.Add("Error getting tenant context: $_")
#         return $results
#     }

#     Write-Output "Starting policy compliance check for tenant: $tenantId"
    
#     foreach ($policyId in $requiredPolicyIds) {
#         Write-Output "Checking policy assignment for policy ID: $policyId"
        
#         # Get policy definition details
#         try {
#             $policyDefinition = Get-AzPolicyDefinition -Id $policyId -ErrorAction Stop
#             $policyDisplayName = $policyDefinition.Properties.DisplayName
#         } catch {
#             $ErrorList.Add("Error getting policy definition: $_")
#             $policyDisplayName = "Unknown Policy"
#         }
        
#         # Check for policy assignments at tenant level
#         try {
#             $assignments = Get-AzPolicyAssignment -Scope $rootScope -PolicyDefinitionId $policyId -ErrorAction Stop
#             # Write-Output "Raw assignments output:"
#             # $assignments | Format-List
#             $tenantPolicyAssignments = @()
#             if ($assignments -is [array]) {
#                 $tenantPolicyAssignments = $assignments | Where-Object { $null -ne $_ }
#             } else {
#                 if ($null -ne $assignments) {
#                     $tenantPolicyAssignments += $assignments
#                 }
#             }            
#             Write-Output "Final assignments array contains $($tenantPolicyAssignments.Count) items"
#         } catch {
#             $ErrorList.Add("Error getting policy assignments for policy $policyId : $_")
#             $tenantPolicyAssignments = @()
#         }
        
#         # Check if we have any policy assignments (not null and not empty)
#         if ($null -ne $tenantPolicyAssignments -and $tenantPolicyAssignments.Count -gt 0) {
#             Write-Output "Found $($tenantPolicyAssignments.Count) assignments matching this policy ID"
            
#             $hasExemptions = $false
            
#             # Check for policy exemptions
#             foreach ($assignment in $tenantPolicyAssignments) {
#                 try {
#                     if ($null -ne $assignment -and $null -ne $assignment.PolicyAssignmentId ) {
#                         Write-Output "Checking exemptions for assignment: $($assignment.PolicyAssignmentId)"
#                         $policyExemptions = Get-AzPolicyExemption -Scope $rootScope -PolicyAssignmentId $assignment.PolicyAssignmentId  -ErrorAction Stop
#                         if ($policyExemptions) {
#                             $hasExemptions = $true
#                             break
#                         }
#                     } else {
#                         Write-Output "Skipping exemption check for invalid assignment"
#                         continue
#                     }
#                 } catch {
#                     # Only add to ErrorList if it's not the expected null parameter error
#                     if ($_ -notmatch "Cannot validate argument on parameter 'PolicyAssignmentIdFilter'") {
#                         $ErrorList.Add("Error checking policy exemptions: $_")
#                     }
#                     continue
#                 }
#             }
            
#             if ($hasExemptions) {
#                 Write-Output "Policy has exemptions configured at tenant level"
#                 $result = [PSCustomObject]@{
#                     Type = "tenant"
#                     Id = $tenantId
#                     Name = "Tenant ($tenantId)"
#                     DisplayName = "Tenant ($tenantId)"
#                     ComplianceStatus = $false
#                     Comments = "Policy has exemptions configured. All resources must be evaluated by this policy."
#                     ItemName = "$ItemName - $policyDisplayName"
#                     ControlName = $ControlName
#                     ReportTime = $ReportTime
#                     itsgcode = $itsgcode
#                 }
                
#                 if ($EnableMultiCloudProfiles) {
#                     $result = Add-ProfileInformation -Result $result -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
#                 }
                
#                 $results.Add($result) | Out-Null
#                 continue
#             }

#             Write-Output "Policy is assigned at tenant level. Checking compliance states..."
            
#             # Get all policy states for this policy
#             $policyStates = Get-AzPolicyState | Where-Object { $_.PolicyDefinitionId -eq $policyId }

#             # If no resources are found that the policy applies to
#             if ($null -eq $policyStates -or $policyStates.Count -eq 0) {
#                 Write-Output "No resources found that the policy applies to"
#                 $result = [PSCustomObject]@{
#                     Type = "tenant"
#                     Id = $tenantId
#                     Name = "Tenant ($tenantId)"
#                     DisplayName = "Tenant ($tenantId)"
#                     ComplianceStatus = $true
#                     Comments = "No applicable resources found. Policy is assigned at tenant level."
#                     ItemName = "$ItemName - $policyDisplayName"
#                     ControlName = $ControlName
#                     ReportTime = $ReportTime
#                     itsgcode = $itsgcode
#                 }
                
#                 if ($EnableMultiCloudProfiles) {
#                     $result = Add-ProfileInformation -Result $result -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
#                 }
                
#                 $results.Add($result) | Out-Null
#                 continue
#             }

#             # Check if any resources are non-compliant
#             $nonCompliantResources = $policyStates | 
#                 Where-Object { $_.ComplianceState -eq "NonCompliant" -or $_.IsCompliant -eq $false }
            
#             if ($nonCompliantResources) {
#                 Write-Output "Found $($nonCompliantResources.Count) non-compliant resources"
#                 foreach ($resource in $nonCompliantResources) {
#                     $result = [PSCustomObject]@{
#                         Type = $resource.ResourceType
#                         Id = $resource.ResourceId
#                         Name = $resource.ResourceGroup + "/" + ($resource.ResourceId -split '/')[-1]
#                         DisplayName = $resource.ResourceGroup + "/" + ($resource.ResourceId -split '/')[-1]
#                         ComplianceStatus = $false
#                         Comments = $msgTable.policyNotCompliant
#                         ItemName = "$ItemName - $policyDisplayName"
#                         ControlName = $ControlName
#                         ReportTime = $ReportTime
#                         itsgcode = $itsgcode
#                     }
                    
#                     if ($EnableMultiCloudProfiles) {
#                         $result = Add-ProfileInformation -Result $result -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
#                     }
                    
#                     $results.Add($result) | Out-Null
#                 }
#             } else {
#                 Write-Output "All resources are compliant with the policy"
#                 $result = [PSCustomObject]@{
#                     Type = "tenant"
#                     Id = $tenantId
#                     Name = "All Resources"
#                     DisplayName = "All Resources"
#                     ComplianceStatus = $true
#                     Comments = $msgTable.policyCompliant
#                     ItemName = "$ItemName - $policyDisplayName"
#                     ControlName = $ControlName
#                     ReportTime = $ReportTime
#                     itsgcode = $itsgcode
#                 }
                
#                 if ($EnableMultiCloudProfiles) {
#                     $result = Add-ProfileInformation -Result $result -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
#                 }
                
#                 $results.Add($result) | Out-Null
#             }
#         } else {
#             Write-Output "Policy is not assigned at tenant level"
#             $result = [PSCustomObject]@{
#                 Type = "tenant"
#                 Id = $tenantId
#                 Name = "Tenant ($tenantId)"
#                 DisplayName = "Tenant ($tenantId)"
#                 ComplianceStatus = $false
#                 Comments = $msgTable.policyNotConfigured
#                 ItemName = "$ItemName - $policyDisplayName (Not Assigned)"
#                 ControlName = $ControlName
#                 ReportTime = $ReportTime
#                 itsgcode = $itsgcode
#             }
            
#             if ($EnableMultiCloudProfiles) {
#                 $result = Add-ProfileInformation -Result $result -CloudUsageProfiles $CloudUsageProfiles -ModuleProfiles $ModuleProfiles
#             }
            
#             $results.Add($result) | Out-Null
#         }
#     }

#     Write-Output "Completed policy compliance check. Found $($results.Count) results"
#     return $results
# } 