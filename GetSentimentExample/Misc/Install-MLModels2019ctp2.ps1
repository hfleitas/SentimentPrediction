#
# Install-MLModels.ps1
# Copyright (C) Microsoft.  All rights reserved.
#

# Verify script is being run with elevated privileges
if (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Error "This script must be run as Administrator"
    Exit 1
}

class SqlInstance
{
    static $Languages = @{`
        'R' = @{`
            'ModelsPath' = 'library\MicrosoftML\mxLibs\x64';`
            'SharedKey' = 'sql_shared_mr';`
            'DllName' = 'MR';`
            'ConfigNode' = 'mrs' };`
        'Python' = @{`
            'ModelsPath' = 'Lib\site-packages\microsoftml\mxLibs';`
            'SharedKey' = 'sql_shared_mpy';`
            'DllName' = 'MPY';`
            'ConfigNode' = 'mpy' }}

    [bool]$IsShared
    [Version]$MlmVersion
    [Version]$MlsVersion
    [string]$Name
    [string]$RootPath
    [string]$RSetupPath
    [string]$SqlVersion

    SqlInstance($isShared, $instanceName, $sqlVersion)
    {
        $this.IsShared = $isShared
        $this.Name = $instanceName
        $this.SqlVersion = $sqlVersion
        
        if ($this.IsShared)
        {
            foreach ($language in [SqlInstance]::Languages.Values)
            {
                $sharedRegPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$sqlVersion\$($language.SharedKey)"
                $sharedKey = Get-ItemProperty -Path $sharedRegPath -ErrorAction "Ignore"

                if ($sharedKey -ne $null)
                {
                    $this.RootPath = (Get-Item($sharedKey.Path)).Parent.FullName
                    $this.RSetupPath = "$($this.RootPath)\Setup Bootstrap\SQLvNextCTP2.0\x64\RSetup.exe" -f (ConvertSqlVersionToName $sqlVersion)
                    break
                }
            }
        }
        else
        {
            $setupRegPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceName\Setup"
            $this.RootPath = (Get-Item (Get-ItemProperty -Path $setupRegPath -ErrorAction "Ignore").SQLPath).Parent.FullName
            $this.RSetupPath = "{0}\SQLvNextCTP2.0\x64\RSetup.exe" -f`
                (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$sqlVersion\Bootstrap" -ErrorAction "Ignore").BootstrapDir,`
                (ConvertSqlVersionToName $sqlVersion)
        }

        # Set MLS version
        try
        {
            $bindingPath = Join-Path $this.GetLanguageFolder("R") ".sqlbindr.ini"

            if ((Test-Path $bindingPath) -and ((Get-Item -Force $bindingPath).Length -gt 0))
            {
                $this.MlsVersion = Get-Content $bindingPath
                $this.RSetupPath = Join-Path (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\R Server').Path "Setup\rsetup.exe"
            }
            else
            {
                # Get MLS version from XML resource
                foreach ($language in [SqlInstance]::Languages.Values)
                {
                    $dllName = if ($this.IsShared) {"S$($language.DllName)Dll"} else {"I$($language.DllName)Dll"}
                    $dllPath = if ($this.IsShared) {"Shared\$dllName.dll"} else {"MSSQL\Binn\$dllName.dll"}
                    $dllPath = Join-Path $this.RootPath $dllPath

                    if (Test-Path $dllPath)
                    {
                        $assembly = [System.Reflection.Assembly]::LoadFrom($dllPath)
                        $doc = New-Object System.Xml.XmlDocument
                        $doc.Load($assembly.GetManifestResourceStream("$dllName.$dllName.xml"))
                        $this.MlsVersion = $doc.SelectSingleNode("/ConfigurationData/$($language.ConfigNode)").InnerText
                        break
                    }
                }
            }
        }
        catch
        {
            # Ignore exceptions
        }

        # Map MLS version to MLM version
        if ($this.MlsVersion.ToString(3) -eq "9.2.0")
        {
            $this.MlmVersion = "9.2.0.24"
        }
        elseif ($this.MlsVersion.ToString(3) -eq "9.2.1"`
            -or $this.MlsVersion.ToString(3) -eq "9.3.0"`
            -or $this.MlsVersion.ToString(3) -eq "9.4.1")
        {
            $this.MlmVersion = $this.MlsVersion.ToString(3)
        }
        else
        {
            $this.MlmVersion = $this.MlsVersion
        }
    }

    [string] GetLanguageFolder($language)
    {
        $languageFolder = $null

        if ([SqlInstance]::Languages.ContainsKey($language))
        {
            if ($this.IsShared)
            {
                $languageFolder = Join-Path $this.RootPath "$($language)_SERVER".ToUpper()
            }
            else
            {
                $languageFolder = Join-Path $this.RootPath "$($language)_SERVICES".ToUpper()
            }
        }

        return $languageFolder
    }
}

function ConvertSqlVersionToName($sqlVersion)
{
    $sqlVersionName = $null

    foreach ($sqlKey in (Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$sqlVersion" -ErrorAction "Ignore").PSChildName)
    {
        try
        {
            if ($sqlKey -imatch "^SQL(Server)?\d+$")
            {
                $sqlVersionName = $sqlKey
                break
            }
        }
        catch
        {
            # Ignore exceptions
        }
    }

    return $sqlVersionName
}

function GetSqlInstances()
{
    $sqlInstances = @{}

    # Handle shared installs
    foreach ($sqlVersion in (Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' -ErrorAction "Ignore").PSChildName)
    {
        try
        {
            $sqlInstance = [SqlInstance]::new($true, "SHARED_{0}" -f (ConvertSqlVersionToName $sqlVersion).ToUpper(), $sqlVersion)

            if ($sqlInstance.MlmVersion -ne $null)
            {
                $sqlInstances[$sqlInstance.Name] = $sqlInstance
            }
        }
        catch
        {
            # Ignore exceptions
        }
    }

    # Handle per-instance installs
    foreach ($sqlKey in (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL" -ErrorAction "Ignore").PSObject.Properties)
    {
        try
        {
            $versionRegPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$($sqlKey.Value)\MSSQLServer\CurrentVersion"
            $sqlVersion = (Get-ItemProperty -Path $versionRegPath -ErrorAction "Ignore").CurrentVersion -replace '^(\d+)\.(\d).*', '${1}0'
            $sqlInstance = [SqlInstance]::new($false, $sqlKey.Value, $sqlVersion)

            if ($sqlInstance.MlmVersion -ne $null)
            {
                $sqlInstances[$sqlKey.Name] = $sqlInstance
            }
        }
        catch
        {
            # Ignore exceptions
        }
    }

    return $sqlInstances
}

# Handle command-line arguments
if ($Args -ne $null -and $Args.Length -gt 0)
{
    $sqlInstances = GetSqlInstances

    # Handle all instances
    foreach ($arg in $Args)
    {
        if ($sqlInstances.ContainsKey($arg))
        {
            $sqlInstance = $sqlInstances[$arg]

            Write-Host "$($sqlInstance.Name)"

            foreach ($language in [SqlInstance]::Languages.Keys)
            {
                $languageFolder = $sqlInstance.GetLanguageFolder($language)
                if (Test-Path $languageFolder)
                {
                    $modelsPath = [SqlInstance]::Languages[$language].ModelsPath
                    $installDir = Join-Path $languageFolder $modelsPath
                    $rsetupArgs = "/component MLM /version $($sqlInstance.MlmVersion) /language 1033 /destdir `"$installDir`""

                    # Verify models version
                    Write-Host "`tVerifying $language models [$($sqlInstance.MlmVersion)]"
                    &$sqlInstance.RSetupPath "/checkurl $rsetupArgs" 2>&1 > $null
                    if ($lastexitcode -eq -1 -or $lastexitcode -eq 2)
                    {
                        Write-Warning "MLS version $($sqlInstance.MlmVersion) not supported"
                        break
                    }
                    elseif ($lastexitcode -gt 10000)
                    {
                        Write-Warning "Error downloading models [https://go.microsoft.com/fwlink/?LinkId=$lastexitcode&clcid=1033]"
                        break
                    }
                    elseif ($lastexitcode -ne 0)
                    {
                        Write-Warning "rsetup.exe exited with $lastexitcode"
                        break
                    }

                    # Download models, if not already cached
                    &$sqlInstance.RSetupPath "/checkcache $rsetupArgs" 2>&1 > $null
                    if ($lastexitcode -ne 0)
                    {
                        Write-Host "`tDownloading $language models [$Env:TEMP]"
                        &$sqlInstance.RSetupPath "/download $rsetupArgs" 2>&1 > $null

                        if ($lastexitcode -gt 10000)
                        {
                            Write-Warning "Error downloading models [https://go.microsoft.com/fwlink/?LinkId=$lastexitcode&clcid=1033]"
                            break
                        }
                        if ($lastexitcode -ne 0)
                        {
                            Write-Warning "rsetup.exe exited with $lastexitcode"
                            break
                        }
                    }

                    # Install models
                    Write-Host "`tInstalling $language models [$installDir]"
                    &$sqlInstance.RSetupPath "/install $rsetupArgs" 2>&1 > $null
                    if ($lastexitcode -ne 0)
                    {
                        Write-Warning "rsetup.exe exited with $lastexitcode"
                        break
                    }
                }
            }
        }
        else
        {
            Write-Warning "$($arg): invalid instance"
        }
    }
}
else
{
    $sqlInstances = GetSqlInstances

    Write-Host "usage: Install-MLModels.ps1 <INSTANCE> [<INSTANCE> ...]"
    Write-Host
    Write-Host "Available instances:"
    
    # Display available instances
    foreach ($instanceName in $sqlInstances.Keys | Sort-Object)
    {
        Write-Host "`t$($instanceName)"
    }
}
# SIG # Begin signature block
# MIIpeQYJKoZIhvcNAQcCoIIpajCCKWYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA/qzx4sg3cfBuZ
# 5cn5Yxpojw3U755WDxeF+gb92zNOIqCCDYEwggX/MIID56ADAgECAhMzAAABA14l
# HJkfox64AAAAAAEDMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMTgwNzEyMjAwODQ4WhcNMTkwNzI2MjAwODQ4WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDRlHY25oarNv5p+UZ8i4hQy5Bwf7BVqSQdfjnnBZ8PrHuXss5zCvvUmyRcFrU5
# 3Rt+M2wR/Dsm85iqXVNrqsPsE7jS789Xf8xly69NLjKxVitONAeJ/mkhvT5E+94S
# nYW/fHaGfXKxdpth5opkTEbOttU6jHeTd2chnLZaBl5HhvU80QnKDT3NsumhUHjR
# hIjiATwi/K+WCMxdmcDt66VamJL1yEBOanOv3uN0etNfRpe84mcod5mswQ4xFo8A
# DwH+S15UD8rEZT8K46NG2/YsAzoZvmgFFpzmfzS/p4eNZTkmyWPU78XdvSX+/Sj0
# NIZ5rCrVXzCRO+QUauuxygQjAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUR77Ay+GmP/1l1jjyA123r3f3QP8w
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDM3OTY1MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAn/XJ
# Uw0/DSbsokTYDdGfY5YGSz8eXMUzo6TDbK8fwAG662XsnjMQD6esW9S9kGEX5zHn
# wya0rPUn00iThoj+EjWRZCLRay07qCwVlCnSN5bmNf8MzsgGFhaeJLHiOfluDnjY
# DBu2KWAndjQkm925l3XLATutghIWIoCJFYS7mFAgsBcmhkmvzn1FFUM0ls+BXBgs
# 1JPyZ6vic8g9o838Mh5gHOmwGzD7LLsHLpaEk0UoVFzNlv2g24HYtjDKQ7HzSMCy
# RhxdXnYqWJ/U7vL0+khMtWGLsIxB6aq4nZD0/2pCD7k+6Q7slPyNgLt44yOneFuy
# bR/5WcF9ttE5yXnggxxgCto9sNHtNr9FB+kbNm7lPTsFA6fUpyUSj+Z2oxOzRVpD
# MYLa2ISuubAfdfX2HX1RETcn6LU1hHH3V6qu+olxyZjSnlpkdr6Mw30VapHxFPTy
# 2TUxuNty+rR1yIibar+YRcdmstf/zpKQdeTr5obSyBvbJ8BblW9Jb1hdaSreU0v4
# 6Mp79mwV+QMZDxGFqk+av6pX3WDG9XEg9FGomsrp0es0Rz11+iLsVT9qGTlrEOla
# P470I3gwsvKmOMs1jaqYWSRAuDpnpAdfoP7YO0kT+wzh7Qttg1DO8H8+4NkI6Iwh
# SkHC3uuOW+4Dwx1ubuZUNWZncnwa6lL2IsRyP64wggd6MIIFYqADAgECAgphDpDS
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIbTjCCG0oCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAQNeJRyZH6MeuAAAAAABAzAN
# BglghkgBZQMEAgEFAKCBsDAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgtInZ2Go7
# 5tRAlLWnd2GrwmCugjLQi3fv+rF/5p1gKmEwRAYKKwYBBAGCNwIBDDE2MDSgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRyAGmh0dHBzOi8vd3d3Lm1pY3Jvc29mdC5jb20g
# MA0GCSqGSIb3DQEBAQUABIIBAH/DmzKL4weDiF1Sax1ViMmsxnookdB33tM/IDgP
# 1CPAETbKUC7rt0jLtcTp0Labk8szN/yopV2tZiuRC0HvTPDyZWtlonL8a7/yH1vA
# cH1BRsTm5DgMhX4a+hREqIIhDt/6HYblHj1qNkq3TOJa7NIq8sqQthWSrgsnnRyQ
# JSkn93j9E/JbKNw/Qx2TY65rhcYbO4iiCHXBHZgxlm6u7BVNKWgj/Waw8UETA9bA
# giiEbDFgmgQSDdTuOPN0zQieJo4Tp//0VQ9ZW/gciW+FVQnA66RPjyEA95EU2NgC
# fhWvDHwUse4RVEB0arnirHwG8ivsXicu4lzy+6irIZp03AShghjWMIIY0gYKKwYB
# BAGCNwMDATGCGMIwghi+BgkqhkiG9w0BBwKgghivMIIYqwIBAzEPMA0GCWCGSAFl
# AwQCAQUAMIIBUQYLKoZIhvcNAQkQAQSgggFABIIBPDCCATgCAQEGCisGAQQBhFkK
# AwEwMTANBglghkgBZQMEAgEFAAQgqmalPx/ygwVgCrQQSUaaBzBjcq7U4GhdQkmF
# bFK24S8CBltN9cmPDhgTMjAxODA3MjAyMDU0NTQuNjI4WjAEgAIB9KCB0KSBzTCB
# yjELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAldBMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29m
# dCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRT
# UyBFU046QTg0MS00QkI0LUNBOTMxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIHNlcnZpY2WgghQtMIIE8TCCA9mgAwIBAgITMwAAAMHl+LT9DneYPwAAAAAA
# wTANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0xODAxMzExOTAwNDRaFw0xODA5MDcxOTAwNDRaMIHKMQswCQYDVQQGEwJVUzEL
# MAkGA1UECBMCV0ExEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
# aW9ucyBMaW1pdGVkMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpBODQxLTRCQjQt
# Q0E5MzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgc2VydmljZTCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKP+nnUoLXw7M+3uJj7GPVho/DO3
# 8fPvVqFhXJhTuIUXkhe4bSuRSgNO1R/ZBRKuInSuq3Wu9WqoVq3/4J9necFWjSg9
# dn6yEdDlbEHISUNJc846zhox5zVeXyopSnB7liAXtOJdHxYT/1T1v3gz9/55KwY3
# 5LX4/Q8rpSVDJjcT0L7m+Np0LF5Ij/y2pNA8pmYvT2ESDLvUSTt7KG98t774RAWx
# 23G5AJ3PmfN4ziuNo+ZbguVZmbULcYhmTGgvAS4xSWiU1GRhhId8VxU3qOIwt/ZN
# yraknqQly8L600+Ip3EslMuVL/ANNHKjgw7PV7h0njAvh4qr5DOamSjljGMCAwEA
# AaOCARswggEXMB0GA1UdDgQWBBSgw0hV17Eo85XUxNLMozj8HKQxfzAfBgNVHSME
# GDAWgBTVYzpcijGQ80N7fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEugSaBHhkVodHRw
# Oi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNUaW1TdGFQ
# Q0FfMjAxMC0wNy0wMS5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5o
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1RpbVN0YVBDQV8y
# MDEwLTA3LTAxLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MA0GCSqGSIb3DQEBCwUAA4IBAQCjcZUnzcXkZ7nJV2JDjir8EMop7ZLI6cmL7oH+
# VGM+lqV0TtLY6SIKO6OCijvA0YwIoOCJjKj8DvpurbAG3XdqCq2FWHypU/HQFBtI
# kdhaNo54aEO8rdjclOYbJeA9GI/kRfXedzLOEuiVZ0/Dgl+v4hjI3NSac2nbpS76
# d5nwfXDjb/WULySrWzXNAm7IEs/rbBBw0+3qY9rBDix+Kdj94a8r4GH54/Iu2tMw
# fW7RyF4uZTVLennHPPfFhJeG+I/bwUWLyc54I8YtKzP9jQ0f06ZqEvtb/ypEFI6w
# W5x+nw9hV54zhXyoZgu+ZxpzLfd4XzAT/78Pf4gnbPkrz1qCMIIF7TCCA9WgAwIB
# AgIQKMw6Jb+6RKxEmptYa0M5qjANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJv
# b3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMTAwNjIzMjE1NzI0WhcN
# MzUwNjIzMjIwNDAxWjCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9y
# aXR5IDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC5CJ4o5OTs
# Bk5QaLNBxXvrrraOr4G6IkQfZTRpTL5wQBfyFnvief2G7Q059BuorZKQHss9do9a
# 2bWREC48BY2KbSRU5x/tVq2DtFCcFaUXdIhZIPwIxYR202jUbyh4zly481CQRP/j
# Y1++oZoslhUE1gf+HoQh4EIxEcQoNpTPUKRinsnWq3EAslsM5pbUCiSW9f/G1bcb
# 18u3IWKvEtyhXTfjGvsaRpjAm8DnYx8qCJMCfh5qjvKfGInkIoWisYRXQP/1Dthv
# nO3iRTEBzRfpf7CBReOqIUAmoXKqp088AQV+7oNYsV4GY5likXiCtw2TDCRqtBvb
# J+xflQQ/k0ow9ZcYs6f5GaeTMx0ByNsiUlzXJclG+aL7h1lDvptisY0thkQaRqx4
# YX4wCfquicRBKiJmA5E5RZzHiwyoyg0v+1LqDPdjMyOd/rAfrWfWp1ADxgRwY7Us
# sYZaQ7f7rvluKW4hIUEmBozJw+6wwoWTobmF2eYybEtMP9Zdo+W1nXfDnMBVt3QA
# 47g4q4OXUOGaQiQdxsCjMNEaWshSNPdz8ccYHzOteuzLQWDzI5QgwkhFrFxRxi6A
# wuJ3Fb2Fh+02nZaR7gC1o3Dsn+ONgGiDdrqvXXBSIhbiZvu6s8XC9z4vd6bK3sGm
# xkhMwzdRI9Mn17hOcJbwoUR2r3jPmuFmEwIDAQABo1EwTzALBgNVHQ8EBAMCAYYw
# DwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU1fZWy4/oolxiaNE9lJBb186aGMQw
# EAYJKwYBBAGCNxUBBAMCAQAwDQYJKoZIhvcNAQELBQADggIBAKylloy/u66m9tdx
# h0MxVoj9HDJxWzW31PCR8q834hTx8wImBT4WFH8UurhP+4mysufUCcxtuVs7ZGVw
# ZrfysVrfGgLz9VG4Z215879We+SEuSsem0CcJjT5RxiYadgc17bRv49hwmfEte9g
# Q44QGzZJ5CDKrafBsSdlCfjN9Vsq0IQz8+8f8vWcC1iTN6B1oN5y3mx1KmYi9YwG
# MFafQLkwqkB3FYLXi+zA07K9g8V3DB6urxlToE15cZ8PrzDOZ/nWLMwiQXoH8pdC
# GM5ZeRBV3m8Q5Ljag2ZAFgloI1uXLiaaArtXjMW4umliMoCJnqH9wJJ8eyszGYQq
# Y8UAaGL6n0eNmXpFOqfp7e5pQrXzgZtHVhB7/HA2hBhz6u/5l02eMyPdJgu6Krc/
# RNyDJ/+9YVkrEbfKT9vFiwwcMa4y+Pi5Qvd/3GGadrFaBOERPWZFtxhxvskkhdbz
# 1LpBNF0SLSW5jaYTSG1LsAd9mZMJYYF0VyaKq2nj5NnHiMwk2OxSJFwevJEU4pbe
# 6wrant1fs1vb1ILsxiBQhyVAOvvH7s3+M+Vuw4QJVQMlOcDpNV1lMaj2v6AJzSnH
# szYyLtyV84PBWs+LjfbqsyH4pO0eMQ62TBGrYAukEiMiF6M2ZIKRBBLgq28ey1AF
# YbRA/1mGcdHVM2l8qXOKONdkDPFpMIIGcTCCBFmgAwIBAgIKYQmBKgAAAAAAAjAN
# BgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9y
# aXR5IDIwMTAwHhcNMTAwNzAxMjEzNjU1WhcNMjUwNzAxMjE0NjU1WjB8MQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
# AQoCggEBAKkdDbx3EYo6IOz8E5f1+n9plGt0VBDVpQoAgoX77XxoSyxfxcPlYcJ2
# tz5mK1vwFVMnBDEfQRsalR3OCROOfGEwWbEwRA/xYIiEVEMM1024OAizQt2TrNZz
# MFcmgqNFDdDq9UeBzb8kYDJYYEbyWEeGMoQedGFnkV+BVLHPk0ySwcSmXdFhE24o
# xhr5hoC732H8RsEnHSRnEnIaIYqvS2SJUGKxXf13Hz3wV3WsvYpCTUBR0Q+cBj5n
# f/VmwAOWRH7v0Ev9buWayrGo8noqCjHw2k4GkbaICDXoeByw6ZnNPOcvRLqn9Nxk
# vaQBwSAJk3jN/LzAyURdXhacAQVPIk0CAwEAAaOCAeYwggHiMBAGCSsGAQQBgjcV
# AQQDAgEAMB0GA1UdDgQWBBTVYzpcijGQ80N7fEYbxTNoWoVtVTAZBgkrBgEEAYI3
# FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAf
# BgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBH
# hkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNS
# b29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUF
# BzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0Nl
# ckF1dF8yMDEwLTA2LTIzLmNydDCBoAYDVR0gAQH/BIGVMIGSMIGPBgkrBgEEAYI3
# LgMwgYEwPQYIKwYBBQUHAgEWMWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9QS0kv
# ZG9jcy9DUFMvZGVmYXVsdC5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBs
# AF8AUABvAGwAaQBjAHkAXwBTAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcN
# AQELBQADggIBAAfmiFEN4sbgmD+BcQM9naOhIW+z66bM9TG+zwXiqf76V20ZMLPC
# xWbJat/15/B4vceoniXj+bzta1RXCCtRgkQS+7lTjMz0YBKKdsxAQEGb3FwX/1z5
# Xhc1mCRWS3TvQhDIr79/xn/yN31aPxzymXlKkVIArzgPF/UveYFl2am1a+THzvbK
# egBvSzBEJCI8z+0DpZaPWSm8tv0E4XCfMkon/VWvL/625Y4zu2JfmttXQOnxzplm
# kIz/amJ/3cVKC5Em4jnsGUpxY517IW3DnKOiPPp/fZZqkHimbdLhnPkd/DjYlPTG
# pQqWhqS9nhquBEKDuLWAmyI4ILUl5WTs9/S/fmNZJQ96LjlXdqJxqgaKD4kWumGn
# Ecua2A5HmoDF0M2n0O99g/DhO3EJ3110mCIIYdqwUB5vvfHhAN/nMQekkzr3ZUd4
# 6PioSKv33nJ+YWtvd6mBy6cJrDm77MbL2IK0cs0d9LiFAR6A+xuJKlQ5slvayA1V
# mXqHczsI5pgt6o3gMy4SKfXAL1QnIffIrE7aKLixqduWsqdCosnPGUFN4Ib5Kpqj
# EWYw07t0MkvfY3v1mYovG8chr1m1rtxEPJdQcdeh0sVV42neV8HR3jDA/czmTfsN
# v11P6Z0eGTgvvM9YBS7vDaBQNdrvCScc1bN+NR4Iuto229Nfj950iEkSoYICzjCC
# AjcCAQEwgfihgdCkgc0wgcoxCzAJBgNVBAYTAlVTMQswCQYDVQQIEwJXQTEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0w
# KwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAk
# BgNVBAsTHVRoYWxlcyBUU1MgRVNOOkE4NDEtNEJCNC1DQTkzMSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBzZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQBkWmMX
# CNAVyMfdXagMHrZAdMJc8qCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwMA0GCSqGSIb3DQEBBQUAAgUA3vxorzAiGA8yMDE4MDcyMDIxNTcwM1oY
# DzIwMTgwNzIxMjE1NzAzWjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDe/GivAgEA
# MAoCAQACAiijAgH/MAcCAQACAhD3MAoCBQDe/bovAgEAMDYGCisGAQQBhFkKBAIx
# KDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZI
# hvcNAQEFBQADgYEAZNR3SalVsHvRIN7lOapW0NeAGUwClnpEWgXkf515ABZg4/4F
# rxm5vUl1ThmeCzpF7ns3TUamppXTEvFnd0X7DPsU0zdMEePoOrLJR/wGyZ97uYuS
# zayDTRzUVB3Vbkchs8boHqQbwoepfdbiUR2bQ5Gh3Hy9IE1zKbBECW4es7MxggMN
# MIIDCQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAMHl
# +LT9DneYPwAAAAAAwTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCD8eDeMSbpBXEUUtErFeqFo0avX
# SQ8v5IblRCLS1MlVxTCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIDDFz0Xa
# quH0WM6/4cCkzynQIOE57FkIUZcRH2JLwqs0MIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAADB5fi0/Q53mD8AAAAAAMEwIgQggyI5tDcc
# glK3kErTs4AtLyDLeKDcC7RomC3HfoXSe8cwDQYJKoZIhvcNAQELBQAEggEAE6Nc
# kDq8W0wU0nKa3rCWkWHEqNvP2T0GKPc9YcTDXF8edpYIuftUxS3RUAy4Xn1CYqFc
# tFNJMXfAgU1xyIvp0jpz24owuYiKI/QH5xpN7fNr0rGNwyQZmvTLJx4UrcT4q7Xu
# xmBtCv7BG81pOVqZs2DpDCg6sWElPEi1Q41/QH0LKd1c84jXwVSXdwSvqCcq9ApT
# NxWlMMZgIHX3XKJ/7Gulwxps56pf1bPcPO+nuNHvnkFfV9WSTS4cPTyp0PAdR8QB
# r1R7sbzbfQgzLBqtudR6oNodi5IKTGdG2KQ/qu21LQAXTuTq1j3q/dE+GO9ohmmG
# 1iQ/IeyF7O69U9jQVg==
# SIG # End signature block
