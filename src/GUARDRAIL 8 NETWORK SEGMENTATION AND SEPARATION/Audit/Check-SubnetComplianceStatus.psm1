
function Get-SubnetComplianceInformation {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $ControlName,
        [Parameter(Mandatory=$true)]
        [string]
        $WorkSpaceID,
        [Parameter(Mandatory=$true)]
        [string]
        $workspaceKey,
        [Parameter(Mandatory=$false)]
        [string]
        $LogType="GuardrailsCompliance",
        [Parameter(Mandatory=$false)]
        [array]
        $ExcludedSubnets,
        [hashtable] $msgTable,
        [Parameter(Mandatory=$true)]
        [string]
        $ReportTime,
        [Parameter(Mandatory=$true)]
        [string]
        $CBSSubscriptionName
    )
    #module for Tags handling
    #import-module '..\..\GUARDRAIL COMMON\Get-Tags.psm1'
    [PSCustomObject] $SubnetList = New-Object System.Collections.ArrayList
    $reservedSubnetNames=@("GatewaySubnet","AzureFirewallSubnet","AzureBastionSubnet","AzureFirewallManagementSubnet","RouteServerSubnet")
    $allexcluded=$ExcludedSubnets+$reservedSubnetNames

    try {
        $subs=Get-AzSubscription -ErrorAction Stop | Where-Object {$_.State -eq 'Enabled' -and $_.Name -ne $CBSSubscriptionName}  
    }
    catch {
        Add-LogEntry 'Error' "Failed to execute the 'Get-AzSubscription' command--verify your permissions and the installion of the Az.Accounts module; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
        throw "Error: Failed to execute the 'Get-AzSubscription'--verify your permissions and the installion of the Az.Accounts module; returned error message: $_"                
    }

    if ($ExcludedSubnets -ne $null)
    {
        $ExcludedSubnetsList=$ExcludedSubnets.Split(",")
    }
    foreach ($sub in $subs)
    {
        Write-Verbose "Selecting subscription: $($sub.Name)"
        Select-AzSubscription -SubscriptionObject $sub
        
        $VNets=Get-AzVirtualNetwork
        Write-Debug "Found $($VNets.count) VNets."
        if ($VNets)
        {
            foreach ($VNet in $VNets)
            {
                Write-Debug "Working on $($VNet.Name) VNet..."
                $ev=get-tagValue -tagKey "ExcludeFromCompliance" -object $VNet
                if ($ev -ne "true")
                {
                    #Handles the subnets
                    foreach ($subnet in Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $VNet)
                    {
                        Write-Debug "Working on $($subnet.Name) Subnet..."
                        if ($subnet.Name -notin $allexcluded)
                        {
                            #checks NSGs
                            $ComplianceStatus=$false
                            $Comments = $msgTable.noNSG
                            $MitigationCommands=@"
# https://docs.microsoft.com/en-us/powershell/module/az.network/set-azvirtualnetworksubnetconfig?view=azps-8.0.0#2-add-a-network-security-group-to-a-subnet
#Creates NSG Resource for subnet $($subnet.Name)
Select-azsubscription $($sub.SubscriptionId)
`$nsg=New-AzNetworkSecurityGroup -Name '$($subnet.Name)-nsg' -ResourceGroupName $($vnet.ResourceGroupName) -Location $($VNet.Location)
# Assign NSG to subnet
`$subnet=(Get-AzVirtualNetwork -ResourceGroupName $($vnet.ResourceGroupName) -Name $($vnet.Name)).Subnets | Where-Object Name -eq $($subnet.Name)
`$subnet.NetworkSecurityGroup = `$nsg
Get-AzVirtualNetwork -ResourceGroupName $($vnet.ResourceGroupName) -Name $($vnet.Name) | set-azvirtual-network
"@
                            if ($null -ne $subnet.NetworkSecurityGroup)
                            {
                                Write-Debug "Found $($subnet.NetworkSecurityGroup.Id.Split("/")[8]) NSG"
                                #Add routine to analyze NSG regarding standard rules.
                                $nsg=Get-AzNetworkSecurityGroup -Name $subnet.NetworkSecurityGroup.Id.Split("/")[8] -ResourceGroupName $subnet.NetworkSecurityGroup.Id.Split("/")[4]
                                if ($nsg.SecurityRules.count -ne 0) #NSG has other rules on top of standard rules.
                                {
                                    $LastSecurityRule=($nsg.SecurityRules | Sort-Object Priority -Descending)[0]
                                    if ($LastSecurityRule.DestinationAddressPrefix -eq '*' -and $LastSecurityRule.Access -eq "Deny") # Determine all criteria for good or bad here...
                                    {
                                        $ComplianceStatus=$true
                                        $Comments = $msgTable.subnetCompliant
                                        $MitigationCommands="N/A"
                                    }
                                    else {
                                        $ComplianceStatus=$false
                                        $Comments = $msgTable.nsgConfigDenyAll
                                        $MitigationCommands=@"
Select-azsubscription $($sub.SubscriptionId)
`$nsg=Get-AzNetworkSecurityGroup -Name $($subnet.NetworkSecurityGroup.Id.Split("/")[8]) -ResourceGroupName $($subnet.NetworkSecurityGroup.Id.Split("/")[4])
`$RuleParams = @{
    'Name'                     = 'Denyall'
    'NetworkSecurityGroup'     = `$nsg
    'Protocol'                 = '*'
    'Direction'                = 'Inbound'
    'Priority'                 = 4096
    'SourceAddressPrefix'      = '*'
    'SourcePortRange'          = '*'
    'DestinationAddressPrefix' = '*'
    'DestinationPortRange'     = '*'
    'Access'                   = 'Deny'
    }
Add-AzNetworkSecurityRuleConfig @RuleParams | Set-AzNetworkSecurityGroup
"@
                                    }
                                }
                                else {
                                    #NSG is present but has no custom rules at all.
                                    $ComplianceStatus=$false
                                    $Comments = $msgTable.nsgCustomRule
                                    $MitigationCommands=@"
Select-azsubscription $($sub.SubscriptionId)
`$nsg=Get-AzNetworkSecurityGroup -Name $($subnet.NetworkSecurityGroup.Id.Split("/")[8]) -ResourceGroupName $($subnet.NetworkSecurityGroup.Id.Split("/")[4])
`$RuleParams = @{
    'Name'                     = 'Denyall'
    'NetworkSecurityGroup'     = `$nsg
    'Protocol'                 = '*'
    'Direction'                = 'Inbound'
    'Priority'                 = 4096
    'SourceAddressPrefix'      = '*'
    'SourcePortRange'          = '*'
    'DestinationAddressPrefix' = '*'
    'DestinationPortRange'     = '*'
    'Access'                   = 'Deny'
    }
Add-AzNetworkSecurityRuleConfig @RuleParams | Set-AzNetworkSecurityGroup
"@
                                }
                            }
                            $SubnetObject = [PSCustomObject]@{ 
                                SubscriptionName  = $sub.Name 
                                SubnetName="$($VNet.Name)\$($subnet.Name)"
                                ComplianceStatus = $ComplianceStatus
                                Comments = $Comments
                                ItemName = $msgTable.networkSegmentation
                                ControlName = $ControlName
                                MitigationCommands=$MitigationCommands
                                ReportTime = $ReportTime
                            }
                            $SubnetList.add($SubnetObject) | Out-Null

                            #Checks Routes
                            if ($subnet.RouteTable)
                            {
                                $UDR=$subnet.RouteTable.Id.Split("/")[8]
                                Write-Debug "Found $UDR UDR"
                                $routeTable=Get-AzRouteTable -ResourceGroupName $subnet.RouteTable.Id.Split("/")[4] -name $UDR
                                $ComplianceStatus=$true
                                $Comments= $msgTable.subnetCompliant
                                $MitigationCommands="N/A"
                                foreach ($route in $routeTable.Routes)
                                {
                                    if ($route.NextHopType -ne "VirtualAppliance")
                                    {
                                        $ComplianceStatus=$false
                                        $Comments = $msgTable.routeNVA
                                        $MitigationCommands = $msgTable.routeNVAMitigation
                                    }
                                }
                            }
                            else {
                                $ComplianceStatus=$false
                                $Comments= $msgTable.noUDR
                                $MitigationCommands = $msgTable.noUDRMitigation
                            }
                        }
                        else { #subnet excluded
                            $ComplianceStatus=$true
                            $Comments=$msgTable.subnetExcluded
                            $MitigationCommands="N/A"                            
                        }
                        $SubnetObject = [PSCustomObject]@{ 
                            SubscriptionName  = $sub.Name 
                            SubnetName="$($VNet.Name)\$($subnet.Name)"
                            ComplianceStatus = $ComplianceStatus
                            Comments = $Comments
                            ItemName = $msgTable.networkSeparation
                            ControlName = $ControlName
                            ReportTime = $ReportTime
                            MitigationCommands=$MitigationCommands
                        }
                        $SubnetList.add($SubnetObject) | Out-Null
                    }
                }
                else {
                    Write-Verbose "Excluding $($VNet.Name) based on tagging."
                }    
            }
        }
    }
    Write-Output "Listing $($SubnetList.Count) List members."
    foreach ($s in $SubnetList)
    {
        Write-Output "Subnet: $($s.SubnetName) - Compliant: $($s.ComplianceStatus) Comments: $($s.Comments)"
    }
    $JSONSubnetList = ConvertTo-Json -inputObject $SubnetList 

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
    -sharedkey $workspaceKey `
    -body $JSONSubnetList `
    -logType $LogType `
    -TimeStampField Get-Date 
}

# SIG # Begin signature block
# MIInpwYJKoZIhvcNAQcCoIInmDCCJ5QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB3QOs5yC622TxQ
# 5UCmw+xirtR4OHkX/Y6fZPGT6Mun9KCCDYUwggYDMIID66ADAgECAhMzAAACU+OD
# 3pbexW7MAAAAAAJTMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMzAwWhcNMjIwOTAxMTgzMzAwWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDLhxHwq3OhH+4J+SX4qS/VQG8HybccH7tnG+BUqrXubfGuDFYPZ29uCuHfQlO1
# lygLgMpJ4Geh6/6poQ5VkDKfVssn6aA1PCzIh8iOPMQ9Mju3sLF9Sn+Pzuaie4BN
# rp0MuZLDEXgVYx2WNjmzqcxC7dY9SC3znOh5qUy2vnmWygC7b9kj0d3JrGtjc5q5
# 0WfV3WLXAQHkeRROsJFBZfXFGoSvRljFFUAjU/zdhP92P+1JiRRRikVy/sqIhMDY
# +7tVdzlE2fwnKOv9LShgKeyEevgMl0B1Fq7E2YeBZKF6KlhmYi9CE1350cnTUoU4
# YpQSnZo0YAnaenREDLfFGKTdAgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUlZpLWIccXoxessA/DRbe26glhEMw
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzQ2NzU5ODAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AKVY+yKcJVVxf9W2vNkL5ufjOpqcvVOOOdVyjy1dmsO4O8khWhqrecdVZp09adOZ
# 8kcMtQ0U+oKx484Jg11cc4Ck0FyOBnp+YIFbOxYCqzaqMcaRAgy48n1tbz/EFYiF
# zJmMiGnlgWFCStONPvQOBD2y/Ej3qBRnGy9EZS1EDlRN/8l5Rs3HX2lZhd9WuukR
# bUk83U99TPJyo12cU0Mb3n1HJv/JZpwSyqb3O0o4HExVJSkwN1m42fSVIVtXVVSa
# YZiVpv32GoD/dyAS/gyplfR6FI3RnCOomzlycSqoz0zBCPFiCMhVhQ6qn+J0GhgR
# BJvGKizw+5lTfnBFoqKZJDROz+uGDl9tw6JvnVqAZKGrWv/CsYaegaPePFrAVSxA
# yUwOFTkAqtNC8uAee+rv2V5xLw8FfpKJ5yKiMKnCKrIaFQDr5AZ7f2ejGGDf+8Tz
# OiK1AgBvOW3iTEEa/at8Z4+s1CmnEAkAi0cLjB72CJedU1LAswdOCWM2MDIZVo9j
# 0T74OkJLTjPd3WNEyw0rBXTyhlbYQsYt7ElT2l2TTlF5EmpVixGtj4ChNjWoKr9y
# TAqtadd2Ym5FNB792GzwNwa631BPCgBJmcRpFKXt0VEQq7UXVNYBiBRd+x4yvjqq
# 5aF7XC5nXCgjbCk7IXwmOphNuNDNiRq83Ejjnc7mxrJGMIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGXgwghl0AgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAJT44Pelt7FbswAAAAA
# AlMwDQYJYIZIAWUDBAIBBQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIFxb
# O730x1a0CXAFCRfrtDtoyFooPe9bohhWFDB09UEvMEQGCisGAQQBgjcCAQwxNjA0
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEcgBpodHRwczovL3d3dy5taWNyb3NvZnQu
# Y29tIDANBgkqhkiG9w0BAQEFAASCAQCxSrI2/c2XUjtKE7DlBUAZ6984vyjYSNFn
# qgv7z3uKjtWrjkFOktLSScoOJsId9jFbr9r+mDAR/kAaNClenLtivB57lWdNgorp
# iGLR7ZR+GQEgL6wdetVqA32FhI50cM4s3A1T+6eqvzOT2iW2VN/M7lodRC3wxSbL
# MzN/m8ZkuZZt6z/7qbsElPSmtDRZjCtp1lCLO+LNKVY3y/DPE5CYo7Cb6JYnspjk
# b0MOWtJj2zA/cMkltEVLPazQV0PD8DxosQto6En7r0enfhgCC1zPHOwAXOA63JRY
# dwGNDABOG+kmRi+DmibvOojXB+wdLSqxM7qTu64cxsCPp1yJkIUioYIXADCCFvwG
# CisGAQQBgjcDAwExghbsMIIW6AYJKoZIhvcNAQcCoIIW2TCCFtUCAQMxDzANBglg
# hkgBZQMEAgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEE
# AYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIAEssEir40M0GUeLMU7xS+U0P6zlQaK7
# 7VAUVrzxJ6KqAgZigqXXLToYEzIwMjIwNjAyMjA1NTMwLjg0NlowBIACAfSggdCk
# gc0wgcoxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNV
# BAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxl
# cyBUU1MgRVNOOjhBODItRTM0Ri05RERBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloIIRVzCCBwwwggT0oAMCAQICEzMAAAGZyI+vrbZ9vosA
# AQAAAZkwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwHhcNMjExMjAyMTkwNTE2WhcNMjMwMjI4MTkwNTE2WjCByjELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFt
# ZXJpY2EgT3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046OEE4Mi1F
# MzRGLTlEREExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Uw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC4E/lXXKMsy9rVa2a8bRb0
# Ar/Pj4+bKiAgMgKayvCMFn3ddGof8eWFgJWp5JdKjWjrnmW1r9tHpcP2kFpjXp2U
# drj55jt5NYi1MERcoIo+E29XuCwFAMJftGdvsWea/OTQPIFsZEWqEteXdRncyVwc
# t5xFzBIC1JWCdmfc7R59RMIyvgWjIz8356mweowkOstN1fe53KIJ8flrYILIQWsN
# RMOT3znAGwIb9kyL54C6jZjFxOSusGYmVQ+Gr/qZQELw1ipx9s5jNP1LSpOpfTEB
# Fu+y9KLNBmMBARkSPpTFkGEyGSwGGgSdOi6BU6FPK+6urZ830jrRemK4JkIJ9tQh
# lGcIhAjhcqZStn+38lRjVvrfbBI5EpI2NwlVIK2ibGW7sWeTAz/yNPNISUbQhGAJ
# se/OgGj/1qz/Ha9mqfYZ8BHchNxn08nWkqyrjrKicQyxuD8mCatTrVSbOJYfQyZd
# HR9a4vgyGeZEXBYQNAlIuB37QCOAgs/VeDU8M4dc/IlrTyC0uV1SS4Gk8zV+5X5e
# Ru+XORN8FWqzI6k/9y6cWwOWMK6aUN1XqLcaF/sm9rX84eKW2lhDc3C31WLjp8UO
# fOHZfPuyy54xfilnhhCPy4QKJ9jggoqqeeEhCEfgDYjy+PByV/e5HDB2xHdtlL93
# wltAkI3aCxo84kVPBCa0OwIDAQABo4IBNjCCATIwHQYDVR0OBBYEFI26Vrg+nGWv
# rvIh0dQPEonENR0QMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8G
# A1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBs
# BggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUy
# MDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgw
# DQYJKoZIhvcNAQELBQADggIBAHGzWh29ibBNro3ns8E3EOHGsLB1Gzk90SFYUKBi
# lIu4jDbR7qbvXNd8nnl/z5D9LKgw3T81jqy5tMiWp+p4jYBBk3PRx1ySqLUfhF5Z
# MWolRzW+cQZGXV38iSmdAUG0CpR5x1rMdPIrTczVUFsOYGqmkoUQ/dRiVL4iAXJL
# CNTj4x3YwIQcCPt0ijJVinPIMAYzA8f99BbeiskyI0BHGAd0kGUX2I2/puYnlyS8
# toBnANjh21xgvEuaZ2dvRqvWk/i1XIlO67au/XCeMTvXhPOIUmq80U32Tifw3SSi
# BKTyir7moWH1i7H2q5QAnrBxuyy//ZsDfARDV/Atmj5jr6ATfRHDdUanQpeoBS+i
# ylNU6RARu8g+TMCu/ZndZmrs9w+8galUIGg+GmlNk07fXJ58Oc+qFqgNAsNkMi+d
# SzKkWGA4/klJFn0XichXL8+t7KOayXKGzQja6CdtCjisnyS8hbv4PKhaeMtf68wJ
# WKKOs0tt2AJfYC5vSbH9ck8BGj2e/yQXEZEu88L5/fHK5XUk/IKXx3zaLkxXTSZ4
# 3Ea/WKXVBzMasHZ3Pmny0moEekAXx1UhLNNYv4Vum33VirxSB6r/GKQxFSHu7yFf
# rWQpYyyDH119TmhAedS8T1VabqdtO5ZP2E14TK82Vyxy3xEPelOo4dRIlhm7XY6k
# 9B68MIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0B
# AQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAG
# A1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAw
# HhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOTh
# pkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xP
# x2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ
# 3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOt
# gFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYt
# cI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXA
# hjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0S
# idb9pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSC
# D/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEB
# c8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh
# 8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8Fdsa
# N8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkr
# BgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q
# /y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBR
# BgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsG
# AQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAP
# BgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjE
# MFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kv
# Y3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEF
# BQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEB
# CwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnX
# wnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOw
# Bb6J6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jf
# ZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ
# 5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+
# ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgs
# sU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6
# OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p
# /cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6
# TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784
# cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAs4wggI3
# AgEBMIH4oYHQpIHNMIHKMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYD
# VQQLEx1UaGFsZXMgVFNTIEVTTjo4QTgyLUUzNEYtOUREQTElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAku/zYujn
# qapN6BJ9MJ5jtgDrlOuggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQUFAAIFAOZDjO0wIhgPMjAyMjA2MDMwMzI0MjlaGA8y
# MDIyMDYwNDAzMjQyOVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5kOM7QIBADAK
# AgEAAgIJYwIB/zAHAgEAAgIRrzAKAgUA5kTebQIBADA2BgorBgEEAYRZCgQCMSgw
# JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
# DQEBBQUAA4GBAGwHbGmc9P2BPp6kcEG3/teqqsGYK3rkF0JcTrCVagLByUdNCzKS
# jNDFOU+rQh69f0lHagRXjDyhwjcldzYVZpphhd+9/LdIQFstOaJBCFbLgRUwBA6k
# EMNtx75BKjKt8TFbvJinZR5OFWnTFT5wesZwTFa6bMGO+syi8rYGXHVbMYIEDTCC
# BAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
# MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGZyI+v
# rbZ9vosAAQAAAZkwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsq
# hkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgsr9MMN8H8YW6Oa8qMgtq0Hzi6u99
# McyaMGpsYxvUbsQwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCBmfWn58qKN
# 7WWpBTYOrUO1BSCSnKPLC/G7wCOIc2JsfjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAABmciPr622fb6LAAEAAAGZMCIEINAePUE3Vlgs
# gjJQ5awJaIhU6yts48It1pStLO/M5j9OMA0GCSqGSIb3DQEBCwUABIICADfROYug
# b2ZxUcmALQY4rb+WfUEbgH/dmMDyS3yZD+Y5h8atNqWz4oRraCEg+qG54nNV+aw5
# 2P5eh2ReloDAYEhU55Dii/jwVSM9XmH+IJQlJl4fb0He+7IeDcyiNG0fPrgJ9HmK
# C7JGtVfhrtaJORmVnV2D4gNGxA8QOK16wM3s04NM9bJ9OAs1c7eAPrJEYcHrJFkM
# WFM40SKp2FxJDS/OBFLPWDt8bNL9MNgvC2zqT1egBurGlDiegB036ro4T0R8gkrp
# MKZ1ixYwiWUXuKpH0/6Y+NO4/i7Mq/Xzp8gWU2Fi31I2Eu+mTMH2w0sPl1qoNzVl
# 0uZp9vvT6vIKP8r/JiR3rsw/V8KNPxeke6jC+HGIz1VolGLUHyUBWWmvHyPP3UqG
# ipFouwe9wMaEBqZkvTtVXlrxdDU9UUhX4VzlwD4jAX/Tj4UWJBP2XalBxVEHNYGZ
# djq+Midpe19cBZnmLvfmoDI0vIjaoqx4L9dCTZ8Bpq2i9IvfLQVV8K+tuzR4ZiJ5
# IRnlJoKcfTGIC/s7M0sEHygnXiAWkfK2UFJv/kiKY0HaDxjlmpgFMacdY8yGq7Tr
# JgzFO7qGc69+9vc/NZftZQZzH6P19uVABhRjZTUOJeRx3ycGmorkLbmwyVTvsqQ2
# sQVYQP93riSwD8e3G7aVrSwgZj+on+xzdOEC
# SIG # End signature block
