<#
.SYNOPSIS
   The module will look for a P2 equivalent licensing, Once the solution find any of the following "String Id", the check mark status will be changed from (❌) to (✔️).

Product name: AZURE ACTIVE DIRECTORY PREMIUM P2, String ID: AAD_PREMIUM_P2
Product name: ENTERPRISE MOBILITY + SECURITY E5, String ID: EMSPREMIUM
Product name: Microsoft 365 E5, String ID: SPE_E5

.DESCRIPTION
The module will look for a P2 equivalent licensing, Once the solution find any of the following "String Id", the check mark status will be changed from (❌) to (✔️).

Product name: AZURE ACTIVE DIRECTORY PREMIUM P2, String ID: AAD_PREMIUM_P2
Product name: ENTERPRISE MOBILITY + SECURITY E5, String ID: EMSPREMIUM
Product name: Microsoft 365 E5, String ID: SPE_E5
.PARAMETER Name
        token : auth token 
        FirstBreakGlassUPN: UPN for the first Break Glass account 
        SecondBreakGlassUPN: UPN for the second Break Glass account
        ControlName :-  GUARDRAIL 1 PROTECT ROOT  GLOBAL ADMINS ACCOUNT
        ItemName, 
        WorkSpaceID : Workspace ID to ingest the logs 
        WorkSpaceKey: Workspace Key for the Workdspace 
        LogType: GuardrailsCompliance, it will show in log Analytics search as GuardrailsCompliance_CL
#>
function Get-BreakGlassAccountLicense {
    param (
       [string] $token, 
       [string] $FirstBreakGlassUPN,
       [string] $SecondBreakGlassUPN, 
       [string] $ControlName, 
       [string] $ItemName, 
       [string] $itsgcode,
       [string] $WorkSpaceID, 
       [string] $workspaceKey, 
       [hashtable] $msgTable,
       [string] $LogType,
       [Parameter(Mandatory=$true)]
       [string]
       $ReportTime
       )
    [bool] $IsCompliant= $false
    [string] $Comments= $null

    [PSCustomObject] $BGAccounts = New-Object System.Collections.ArrayList
     
    $FirstBreakGlassAcct= [PSCustomObject]@{
        UserPrincipalName     = $FirstBreakGlassUPN
        ID = $null
        LicenseDetails= $msgTable.bgLicenseNotAssigned
    }
    $SecondBreakGlassAcct= [PSCustomObject]@{
        UserPrincipalName     = $SecondBreakGlassUPN
        ID = $null
        LicenseDetails= $msgTable.bgLicenseNotAssigned
    }
    $BGAccounts.add( $FirstBreakGlassAcct)
    $BGAccounts.add( $SecondBreakGlassAcct)
        
    
    foreach ($BGAccount in $BGAccounts) {
        
        $apiUrl = $("https://graph.microsoft.com/beta/users/" + $BGAccount.UserPrincipalName)

        try {
            $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)" } -Uri $apiUrl -Method Get -ErrorAction Stop
        }
        catch {
            Add-LogEntry 'Error' "Failed to call Microsoft Graph REST API at URL '$apiURL'; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
            Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$apiURL'; returned error message: $_"
        }
        $BGAccount.ID = $Data.id

        $apiUrl = $("https://graph.microsoft.com/beta/users/" + $BGAccount.ID + "/licenseDetails")

        try {
            $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token)" } -Uri $apiUrl -Method Get -ErrorAction Stop
        }
        catch {
            Add-LogEntry 'Error' "Failed to call Microsoft Graph REST API at URL '$apiURL'; returned error message: $_" -workspaceGuid $WorkSpaceID -workspaceKey $WorkSpaceKey
            Write-Error "Error: Failed to call Microsoft Graph REST API at URL '$apiURL'; returned error message: $_"
        }

        if (($data.value).Length -gt 0 ) {
            $BGAccount.LicenseDetails = ($Data.value).skuPartNumber
        }
    }
    if ((($FirstBreakGlassAcct.LicenseDetails -match "EMSPREMIUM") -or ($FirstBreakGlassAcct.LicenseDetails -match "ENTERPRISEPREMIUM")) -and `
        (($SecondBreakGlassAcct.LicenseDetails -match "EMSPREMIUM") -or ($SecondBreakGlassAcct.LicenseDetails -match "ENTERPRISEPREMIUM"))) {
            $IsCompliant= $true
            $Comments= $FirstBreakGlassAcct.UserPrincipalName + $msgTable.bgAssignedLicense +  $FirstBreakGlassAcct.LicenseDetails +
                       $SecondBreakGlassAcct.UserPrincipalName + $msgTable.bgAssignedLicense +  $SecondBreakGlassAcct.LicenseDetails 
   }    else {
             $Comments= $FirstBreakGlassAcct.UserPrincipalName + $msgTable.bgAssignedLicense +  $FirstBreakGlassAcct.LicenseDetails +" & "+
             $SecondBreakGlassAcct.UserPrincipalName + $msgTable.bgAssignedLicense +  $SecondBreakGlassAcct.LicenseDetails 
   }

    $PsObject = [PSCustomObject]@{
        ComplianceStatus = $IsCompliant
        ControlName      = $ControlName
        Comments         = $Comments
        ItemName         = $ItemName
        ReportTime       = $ReportTime
        itsgcode         = $itsgcode
    }
    $JsonObject = convertTo-Json -inputObject $PsObject 

    Send-OMSAPIIngestionFile  -customerId $WorkSpaceID `
        -sharedkey $workspaceKey `
        -body $JsonObject `
        -logType $LogType `
        -TimeStampField Get-Date 
   
}
# SIG # Begin signature block
# MIInqQYJKoZIhvcNAQcCoIInmjCCJ5YCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA9OGbrwHl5lS60
# Y6UyN6jlLp2WI6491Yjyr6Vic4FepKCCDYEwggX/MIID56ADAgECAhMzAAACzI61
# lqa90clOAAAAAALMMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjIwNTEyMjA0NjAxWhcNMjMwNTExMjA0NjAxWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCiTbHs68bADvNud97NzcdP0zh0mRr4VpDv68KobjQFybVAuVgiINf9aG2zQtWK
# No6+2X2Ix65KGcBXuZyEi0oBUAAGnIe5O5q/Y0Ij0WwDyMWaVad2Te4r1Eic3HWH
# UfiiNjF0ETHKg3qa7DCyUqwsR9q5SaXuHlYCwM+m59Nl3jKnYnKLLfzhl13wImV9
# DF8N76ANkRyK6BYoc9I6hHF2MCTQYWbQ4fXgzKhgzj4zeabWgfu+ZJCiFLkogvc0
# RVb0x3DtyxMbl/3e45Eu+sn/x6EVwbJZVvtQYcmdGF1yAYht+JnNmWwAxL8MgHMz
# xEcoY1Q1JtstiY3+u3ulGMvhAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUiLhHjTKWzIqVIp+sM2rOHH11rfQw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDcwNTI5MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAeA8D
# sOAHS53MTIHYu8bbXrO6yQtRD6JfyMWeXaLu3Nc8PDnFc1efYq/F3MGx/aiwNbcs
# J2MU7BKNWTP5JQVBA2GNIeR3mScXqnOsv1XqXPvZeISDVWLaBQzceItdIwgo6B13
# vxlkkSYMvB0Dr3Yw7/W9U4Wk5K/RDOnIGvmKqKi3AwyxlV1mpefy729FKaWT7edB
# d3I4+hldMY8sdfDPjWRtJzjMjXZs41OUOwtHccPazjjC7KndzvZHx/0VWL8n0NT/
# 404vftnXKifMZkS4p2sB3oK+6kCcsyWsgS/3eYGw1Fe4MOnin1RhgrW1rHPODJTG
# AUOmW4wc3Q6KKr2zve7sMDZe9tfylonPwhk971rX8qGw6LkrGFv31IJeJSe/aUbG
# dUDPkbrABbVvPElgoj5eP3REqx5jdfkQw7tOdWkhn0jDUh2uQen9Atj3RkJyHuR0
# GUsJVMWFJdkIO/gFwzoOGlHNsmxvpANV86/1qgb1oZXdrURpzJp53MsDaBY/pxOc
# J0Cvg6uWs3kQWgKk5aBzvsX95BzdItHTpVMtVPW4q41XEvbFmUP1n6oL5rdNdrTM
# j/HXMRk1KCksax1Vxo3qv+13cCsZAaQNaIAvt5LvkshZkDZIP//0Hnq7NnWeYR3z
# 4oFiw9N2n3bb9baQWuWPswG0Dq9YT9kb+Cs4qIIwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZfjCCGXoCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAsyOtZamvdHJTgAAAAACzDAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgkPHpJboF
# /1a2YmFELX0zekj9zFuUTtIE8uhbjh5RquswQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQBLfGyP1Q7x8H7+5IBOs7/XGP+hOzEJ54FsykEnoptl
# xpFybUy0moYPWZFJRBQptknX6BTD3IInbwY83yc/c2skd1JhvNe8lBWL3nqenK5C
# e/kOY1G/Pv1TgTR6XTEqpXTNEPlxyzSPxQhMj4mstrTr3BAJjKuVPGpZAj6NrTfp
# Elkgh1nip29Mt4cBwHLES1IJhGLR9ifE6TmGI9nbIdNfRmyAf+PZBD/YhLEft5EK
# rYwbdWo7r0ocythCnLc/ss3nW3aghunKKZprrbaaDFkQEveSdmquZjXrH7Pmm/2h
# R8QfAcXgW+Idg8FFUEzaMUjPKu/FQsd07L8tzZJTv+0hoYIXCDCCFwQGCisGAQQB
# gjcDAwExghb0MIIW8AYJKoZIhvcNAQcCoIIW4TCCFt0CAQMxDzANBglghkgBZQME
# AgEFADCCAVQGCyqGSIb3DQEJEAEEoIIBQwSCAT8wggE7AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIHR4Dh3RTkSspfBanAtIWZ591Cf20+lOYl12QqzE
# GRUxAgZjKf2NCToYEjIwMjIwOTMwMTQwMzExLjIxWjAEgAIB9KCB1KSB0TCBzjEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEpMCcGA1UECxMgTWlj
# cm9zb2Z0IE9wZXJhdGlvbnMgUHVlcnRvIFJpY28xJjAkBgNVBAsTHVRoYWxlcyBU
# U1MgRVNOOkQ5REUtRTM5QS00M0ZFMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1T
# dGFtcCBTZXJ2aWNloIIRXDCCBxAwggT4oAMCAQICEzMAAAGsZryHIl3ePXsAAQAA
# AawwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
# HhcNMjIwMzAyMTg1MTI5WhcNMjMwNTExMTg1MTI5WjCBzjELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEpMCcGA1UECxMgTWljcm9zb2Z0IE9wZXJh
# dGlvbnMgUHVlcnRvIFJpY28xJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkQ5REUt
# RTM5QS00M0ZFMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAx3gLUMUXYu7HccwrwASU
# x1MXiIb1E7IpBYV6FNd74RfVA6tMEWeEwAo0chBajGQrVbrb+hBBCa0gejyymEy3
# VamQs28Kbctryx1Uve38EDHtRaSZ++6MncoNpKC3dyVzm409SPt7fZTif8Sn2g5z
# 4+/8QdztcYfV8ZG8tFjPCjE/XGQqV66xsjNP9oqfpYLYGCA/OMdeKf0oTuSuIK6o
# D4k2GySR51MclAii1uVH6tlyx7FNKaM75ntHSZ94eJTwOe29m9n/1p31dSEPBQkU
# pnxlm/GeqdlfAViQMo1qBjyDToEXW8O6VuUCzoDiG4/V7um0oWmkHVVmQtQCYhbX
# HEkazeR6J0BNYhXHbawZXJ6ZpPb01+0On+NGwPD9qHC/U2S/pa/KSi8rSQM8hj1M
# Jb1xFu9R4SWT74JUztwiquXxBjeaARDyiLjlXMQFe5jThjUqKNsYthEU1TKlcxEM
# ClX6RyMby5JPXeZIJ/aIyFZFEvP3+PIjB7uWZfPjNTJhySv7Y2bwatKrl9UA+yEg
# 7wBv9o6jr+h7cbdj5yKXyLJEksk3FsxjGJAkpm9vGUIin6kYidoPXfvczso88X/J
# d5PiEbQupcq96WSC2WnN58+uZRW6mNhOB4Z+6lTAXPKZKTglE07W2FEHRsMoMjI0
# xWoS69XVTF1yuJxXSiOB4kcCAwEAAaOCATYwggEyMB0GA1UdDgQWBBRYEZ93BMsf
# QGdKPHxJWphawECOTTAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBf
# BgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
# L2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmww
# bAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0El
# MjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MA0GCSqGSIb3DQEBCwUAA4ICAQB50LUCWFVccKV2Ty2gjMBb1DIhNxF7KFSmzW4P
# rvMILfTx9HNgURL/a8xfujQ5smDMLFPWeLS+RyzxYbYxQiyT3VEI8h4PNNAi0imP
# 1lPP2HS259woabdqGSdGzWGhXXaNEWRxqpcmjV+zK6gqAP4VNPaU6+sSw2MmHnAS
# yL48H+ZWaH8lrRW7yOFQlzWGsFRDliKxDg3TSydnCE6gJ49dt0PocazVyaxdluuR
# Py809hXwucjiXG4n9hphLbSpCvpj0MgcUM1jFltOWxB5ez8qOeFE10WIIagBwsdb
# B5Z5GzOHaJSEx9jX/v13uyiZ+PHpnIk9k6vh8TRRPaX+sFoFOug+kM6+lo6xjoT+
# 14ssx/KevpQ5B4TiVGLDn2yJUbIAaqlMFNt3MAUsEUfjS5uvtUSV2aOIdrXgSRnF
# i9yDMrEqq5vjKspp+j+P1pRvAusvZUwdZylrXwmG/rMiN3TUgaRR2PdQn4kpA0DP
# l7I/JBJk+33CzxvKeh0aUzmdiQcHLus++PjnL5nPuOsuCOC9kiLEazPCorIonjsA
# 8fGsfwaMJC6xu9b00XgsBgqhlkaPs/CZAD5ebAPm19RDQq7MxEWYyk5TO2JMCAmN
# B/1My5zeliakVYSvySxh3CuOt1ZgAsJcD8hBcR0CKxDCPljNOyHhDFNSr69FLGz3
# fIHecjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcN
# AQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAw
# BgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEw
# MB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk
# 4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9c
# T8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWG
# UNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6Gnsz
# rYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2
# LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLV
# wIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTd
# EonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0
# gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFph
# AXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJ
# YfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXb
# GjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJ
# KwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnP
# EP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMw
# UQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggr
# BgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYw
# DwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoY
# xDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtp
# L2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYB
# BQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0B
# AQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U5
# 18JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgAD
# sAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo
# 32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZ
# iefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZK
# PmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RI
# LLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgk
# ujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9
# af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzba
# ukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/
# OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggLPMIIC
# OAIBATCB/KGB1KSB0TCBzjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEpMCcGA1UECxMgTWljcm9zb2Z0IE9wZXJhdGlvbnMgUHVlcnRvIFJpY28x
# JjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkQ5REUtRTM5QS00M0ZFMSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCx
# GtITsLiwSf3oAyGM2RdnRjWKoKCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwMA0GCSqGSIb3DQEBBQUAAgUA5uEByTAiGA8yMDIyMDkzMDA5NDg1
# N1oYDzIwMjIxMDAxMDk0ODU3WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDm4QHJ
# AgEAMAcCAQACAiAgMAcCAQACAhETMAoCBQDm4lNJAgEAMDYGCisGAQQBhFkKBAIx
# KDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZI
# hvcNAQEFBQADgYEAXYy3e2FDrfWUuBIPogOT0Ao4OKo/T+26r1qt/y48hpi0w2/D
# JzuZMkVQlLiAvcKS+Mvua5c4gykomIrsh5ztn7ftDDLMBPct2JwnREc8gFNmMEGx
# 6T2FptRXsvZG/RpFmRFTVxOUJMRk+qn/oE+Uti4mugHgHWtgglbjyAOH9pcxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAaxm
# vIciXd49ewABAAABrDANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAY8tNdOxwOC8HaeiVNd7LGyeUW
# wQa7v0DQ/hBoZNobzzCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIPm3AZKD
# OC8JcQBytXPnqbv0+n5tAl/7T4uDZ9oELML1MIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAGsZryHIl3ePXsAAQAAAawwIgQgDbZy+Lds
# AiAQ9gNmzR0tn19ywz73YKyzbgJm6ErS/o4wDQYJKoZIhvcNAQELBQAEggIAaS5Q
# /jIfTd9zZAt9VOFaIhSAxNamDbaRbzJSKkVvaXMj6XCYzGnX3jGibqEkfXYYOshA
# IVjZNW4e0tbGznoUcoLFT9H0hcKTKQAn2wEXd0HQe4YSMk0U8DOqc9LbT5mX1+eF
# X5YtaVBPZC+lvrkKXhw85AG2XYCRi77t4BDcRMQdXuQ79CAAR+lJ6MvKaXC5vxLl
# ae4lNZ8ibZYlobGV2L4gsgtfAp7J65nhba7KbYpzLzNU4GEvtfO/6AT/nmCt6FHq
# yaSlZrQK6ro3MmV6azi6ouImtR2xEhM+zVIHQ0xDQhQTZBu9Yrh/33kDA1B2s6eL
# t0vTIvrRfUHfPP9Rrq8YngYfE5LHb4TDk36FRfdHz2VFYlTDFPG7ZTDraqktIjRG
# nmGNQ97fK5wnSQ+K+UNVbaUHRkNhe4jZ3ModHwep1a+apV+jNscr2Un5j6A/V7kt
# RyDWmm5vByNFbIq2Q60uDH8xi/AeKwaEBxHrjIj1W25HHRCd4Ck8+z2Xt7ODOGnY
# L0WtH+RF/x2gIL1Mggc0fE5uB9Nr9iWxlLxwNJDCkBn7AQnM3OCEtZpH+0ywbu1J
# uun2ZoJfjFLDdiacZn4ni8rEy94knbKnsFKohEGtkdppzlpEKWANfSc9kmucer7D
# K/uz3knxvPJY6vvcsOgJTmpug4mZqhCL/lIsPHg=
# SIG # End signature block
