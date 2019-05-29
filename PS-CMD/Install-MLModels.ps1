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
                    $this.RSetupPath = "$($this.RootPath)\Setup Bootstrap\{0}\x64\RSetup.exe" -f (ConvertSqlVersionToName $sqlVersion)
                    break
                }
            }
        }
        else
        {
            $setupRegPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceName\Setup"
            $this.RootPath = (Get-Item (Get-ItemProperty -Path $setupRegPath -ErrorAction "Ignore").SQLPath).Parent.FullName
            $this.RSetupPath = "{0}\{1}\x64\RSetup.exe" -f`
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
            $sqlVersion = (Get-ItemProperty -Path $versionRegPath -ErrorAction "Ignore").CurrentVersion -replace '^(\d+)\.(\d).*', '$1$2'
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
                    $installDir = Join-Path $languageFolder $language.ModelsPath
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
                        Write-Warning "Error connecting to download server"
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
                            Write-Warning "Error connecting to download server"
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