function Set-ADtrust {
    <#
    .SYNOPSIS
        Automates AD Trust creation: TrustedHosts, DNS Forwarders, separated Trust Creation (BiDirectional/Inbound/Outbound), Selective Auth, and verification.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SourceDC,
        [Parameter(Mandatory=$true)][string]$SourceDomain,
        [Parameter(Mandatory=$true)][PSCredential]$SourceCred,
        
        [Parameter(Mandatory=$true)][string]$TargetDC,
        [Parameter(Mandatory=$true)][string]$TargetDomain,
        [Parameter(Mandatory=$true)][PSCredential]$TargetCred,

        [Parameter(Mandatory=$false)]
        [ValidateSet("BiDirectional", "Inbound", "Outbound")]
        [string]$Direction = "BiDirectional",

        [Parameter(Mandatory=$false)][switch]$SelectiveAuthentication
    )

    Begin {
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "[*] Starting Automated AD Trust Setup ($Direction)" -ForegroundColor Cyan
        Write-Host "=====================================================" -ForegroundColor Cyan

        function Get-Plaintext {
            param([System.Security.SecureString]$SecureString)
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            return $plain
        }

        # Resolve IPv4 
        $TargetIP = ([System.Net.Dns]::GetHostAddresses($TargetDC) | Where-Object { $_.AddressFamily -eq 'InterNetwork' })[0].IPAddressToString
        $SourceIP = ([System.Net.Dns]::GetHostAddresses($SourceDC) | Where-Object { $_.AddressFamily -eq 'InterNetwork' })[0].IPAddressToString
        
        if (!$TargetIP -or !$SourceIP) {
            Write-Error "Failed to resolve IPv4 for Source or Target DC."
            return
        }

        Write-Host "    [*] Resolved Source IP: $SourceIP" -ForegroundColor Gray
        Write-Host "    [*] Resolved Target IP: $TargetIP" -ForegroundColor Gray
        
        $srcPass = Get-Plaintext $SourceCred.Password
        $tgtPass = Get-Plaintext $TargetCred.Password
    }

    Process {
        # ---------------------------------------------------------------------
        # STEP 1: WinRM TrustedHosts Configuration
        # ---------------------------------------------------------------------
        Write-Host "`n[1] Configuring WinRM TrustedHosts..." -ForegroundColor Yellow
        
        $localTH = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
        if ($localTH -notmatch $TargetIP -and $localTH -notmatch "\*") {
            $newTH = if ([string]::IsNullOrWhiteSpace($localTH)) { "$TargetIP,$TargetDC" } else { "$localTH,$TargetIP,$TargetDC" }
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value $newTH -Force
            Write-Host "    [+] Added Target ($TargetIP) to Local TrustedHosts." -ForegroundColor Green
        } else {
            Write-Host "    [-] Target already in Local TrustedHosts." -ForegroundColor Gray
        }

        try {
            Invoke-Command -ComputerName $TargetIP -Credential $TargetCred -Authentication Negotiate -ScriptBlock {
                param($sIP, $sDC)
                $remoteTH = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
                if ($remoteTH -notmatch $sIP -and $remoteTH -notmatch "\*") {
                    $newRemoteTH = if ([string]::IsNullOrWhiteSpace($remoteTH)) { "$sIP,$sDC" } else { "$remoteTH,$sIP,$sDC" }
                    Set-Item WSMan:\localhost\Client\TrustedHosts -Value $newRemoteTH -Force
                    Write-Host "    [+] Added Source ($sIP) to Remote TrustedHosts." -ForegroundColor Green
                } else {
                    Write-Host "    [-] Source already in Remote TrustedHosts." -ForegroundColor Gray
                }
            } -ArgumentList $SourceIP, $SourceDC
        } catch { Write-Warning "    [!] Failed to configure Remote TrustedHosts: $_" }

        # ---------------------------------------------------------------------
        # STEP 2: DNS Conditional Forwarders
        # ---------------------------------------------------------------------
        Write-Host "`n[2] Configuring DNS Conditional Forwarders..." -ForegroundColor Yellow

        if (!(Get-DnsServerZone -Name $TargetDomain -ErrorAction SilentlyContinue)) {
            Add-DnsServerConditionalForwarderZone -Name $TargetDomain -MasterServers $TargetIP -ReplicationScope Forest
            Write-Host "    [+] Created Local DNS Forwarder for $TargetDomain." -ForegroundColor Green
        } else {
            Write-Host "    [-] Local DNS Forwarder for $TargetDomain already exists." -ForegroundColor Gray
        }

        try {
            Invoke-Command -ComputerName $TargetIP -Credential $TargetCred -Authentication Negotiate -ScriptBlock {
                param($sDomain, $sIP)
                if (!(Get-DnsServerZone -Name $sDomain -ErrorAction SilentlyContinue)) {
                    Add-DnsServerConditionalForwarderZone -Name $sDomain -MasterServers $sIP -ReplicationScope Forest
                    Write-Host "    [+] Created Remote DNS Forwarder for $sDomain." -ForegroundColor Green
                } else {
                    Write-Host "    [-] Remote DNS Forwarder for $sDomain already exists." -ForegroundColor Gray
                }
            } -ArgumentList $SourceDomain, $SourceIP
        } catch { Write-Warning "    [!] Failed to configure Remote DNS: $_" }

        # ---------------------------------------------------------------------
        # STEP 3: Create the Trust
        # ---------------------------------------------------------------------
        Write-Host "`n[3] Creating $Direction Trust..." -ForegroundColor Yellow
        
        # Determine correct netdom syntax based on direction
        if ($Direction -eq "BiDirectional") {
            $netdomAddCmd = "netdom trust $SourceDomain /domain:$TargetDomain /add /twoway /usero:`"$($SourceCred.UserName)`" /passwordo:`"$srcPass`" /userd:`"$($TargetCred.UserName)`" /passwordd:`"$tgtPass`""
        } elseif ($Direction -eq "Outbound") {
            # Source trusts Target
            $netdomAddCmd = "netdom trust $SourceDomain /domain:$TargetDomain /add /usero:`"$($SourceCred.UserName)`" /passwordo:`"$srcPass`" /userd:`"$($TargetCred.UserName)`" /passwordd:`"$tgtPass`""
        } else {
            # Inbound: Target trusts Source (Reverse syntax)
            $netdomAddCmd = "netdom trust $TargetDomain /domain:$SourceDomain /add /usero:`"$($TargetCred.UserName)`" /passwordo:`"$tgtPass`" /userd:`"$($SourceCred.UserName)`" /passwordd:`"$srcPass`""
        }

        Write-Host "    [*] Executing netdom creation command..." -ForegroundColor Gray
        $processAdd = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $netdomAddCmd" -Wait -NoNewWindow -PassThru
        
        if ($processAdd.ExitCode -eq 0) {
            Write-Host "    [+] Trust created successfully (or already exists)." -ForegroundColor Green
        } else {
            Write-Warning "    [!] netdom returned exit code $($processAdd.ExitCode). Trust might already exist."
        }

        # ---------------------------------------------------------------------
        # STEP 4: Configure Selective Authentication
        # ---------------------------------------------------------------------
        if ($SelectiveAuthentication) {
            Write-Host "`n[4] Configuring Selective Authentication..." -ForegroundColor Yellow
            
            # 4A. Apply to Source DC (if BiDirectional or Outbound)
            if ($Direction -in @("BiDirectional", "Outbound")) {
                Write-Host "    [*] Updating Source DC ($SourceDC)..." -ForegroundColor Gray
                $srcSelAuthCmd = "netdom trust $SourceDomain /domain:$TargetDomain /SelectiveAUTH:yes /usero:`"$($SourceCred.UserName)`" /passwordo:`"$srcPass`" /userd:`"$($TargetCred.UserName)`" /passwordd:`"$tgtPass`""
                $procSrc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $srcSelAuthCmd" -Wait -NoNewWindow -PassThru
                if ($procSrc.ExitCode -eq 0) { Write-Host "    [+] Selective Auth enabled on Source DC." -ForegroundColor Green }
            }
            
            # 4B. Apply to Target DC (if BiDirectional or Inbound)
            if ($Direction -in @("BiDirectional", "Inbound")) {
                Write-Host "    [*] Updating Target DC ($TargetDC)..." -ForegroundColor Gray
                try {
                    Invoke-Command -ComputerName $TargetIP -Credential $TargetCred -Authentication Negotiate -ScriptBlock {
                        param($tDom, $sDom, $tUser, $tPass, $sUser, $sPass)
                        $tgtSelAuthCmd = "netdom trust $tDom /domain:$sDom /SelectiveAUTH:yes /usero:`"$tUser`" /passwordo:`"$tPass`" /userd:`"$sUser`" /passwordd:`"$sPass`""
                        $procTgt = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $tgtSelAuthCmd" -Wait -NoNewWindow -PassThru
                        if ($procTgt.ExitCode -eq 0) {
                            Write-Output "    [+] Selective Auth enabled on Target DC."
                        } else {
                            Write-Warning "    [!] Target DC netdom returned exit code $($procTgt.ExitCode)."
                        }
                    } -ArgumentList $TargetDomain, $SourceDomain, $TargetCred.UserName, $tgtPass, $SourceCred.UserName, $srcPass
                } catch { Write-Warning "    [!] Failed to execute SelectiveAuth on Target DC: $_" }
            }
        } else {
            Write-Host "`n[4] Skipping Selective Authentication (Switch not provided)..." -ForegroundColor Gray
        }

        # ---------------------------------------------------------------------
        # STEP 5: Verification & Remediation via Invoke-Command
        # ---------------------------------------------------------------------
        Write-Host "`n[5] Verifying Trust & SelectAuth Status..." -ForegroundColor Yellow

        # VERIFY SOURCE
        Write-Host "    [*] Checking Source DC ($SourceDC)..." -ForegroundColor Gray
        try {
            $sourceCheck = Invoke-Command -ComputerName $SourceDC -ScriptBlock {
                param($td)
                $trust = Get-ADTrust -Filter "Name -eq '$td'" -Properties SelectiveAuthentication
                if ($trust) {
                    [PSCustomObject]@{
                        Direction = $trust.Direction
                        SelectiveAuth = $trust | Select-Object -ExpandProperty SelectiveAuthentication
                    }
                }
            } -ArgumentList $TargetDomain

            if ($sourceCheck) {
                Write-Host "    [+] Trust validated on Source DC." -ForegroundColor Green
                Write-Host "        - Direction: $($sourceCheck.Direction)" -ForegroundColor Cyan
                Write-Host "        - Selective Auth: $($sourceCheck.SelectiveAuth)" -ForegroundColor Cyan
                
                # Remediation Source (Only applicable if Trusting side)
                if ($SelectiveAuthentication -and ($Direction -in @("BiDirectional", "Outbound")) -and ($sourceCheck.SelectiveAuth -eq $false)) {
                    Write-Host "    [!] Source DC is missing Selective Authentication. Remediating..." -ForegroundColor Yellow
                    Invoke-Command -ComputerName $SourceDC -ScriptBlock {
                        param($sDom, $tDom, $sUser, $sPass, $tUser, $tPass)
                        $cmd = "netdom trust $sDom /domain:$tDom /SelectiveAUTH:yes /usero:`"$sUser`" /passwordo:`"$sPass`" /userd:`"$tUser`" /passwordd:`"$tPass`""
                        Start-Process "cmd.exe" "/c $cmd" -Wait -NoNewWindow | Out-Null
                    } -ArgumentList $SourceDomain, $TargetDomain, $SourceCred.UserName, $srcPass, $TargetCred.UserName, $tgtPass
                    Write-Host "    [+] Remediation executed on Source DC." -ForegroundColor Green
                }
            } else { Write-Warning "    [!] Trust not found on Source DC." }
        } catch { Write-Warning "    [!] Source check failed: $_" }


        # VERIFY TARGET
        Write-Host "    [*] Checking Target DC ($TargetDC)..." -ForegroundColor Gray
        try {
            $targetCheck = Invoke-Command -ComputerName $TargetIP -Credential $TargetCred -Authentication Negotiate -ScriptBlock {
                param($sd)
                $trust = Get-ADTrust -Filter "Name -eq '$sd'" -Properties SelectiveAuthentication
                if ($trust) {
                    [PSCustomObject]@{
                        Direction = $trust.Direction
                        SelectiveAuth = $trust | Select-Object -ExpandProperty SelectiveAuthentication
                    }
                }
            } -ArgumentList $SourceDomain

            if ($targetCheck) {
                Write-Host "    [+] Trust validated on Target DC." -ForegroundColor Green
                Write-Host "        - Direction: $($targetCheck.Direction)" -ForegroundColor Cyan
                Write-Host "        - Selective Auth: $($targetCheck.SelectiveAuth)" -ForegroundColor Cyan
                
                # Remediation Target (Only applicable if Trusting side)
                if ($SelectiveAuthentication -and ($Direction -in @("BiDirectional", "Inbound")) -and ($targetCheck.SelectiveAuth -eq $false)) {
                    Write-Host "    [!] Target DC is missing Selective Authentication. Remediating..." -ForegroundColor Yellow
                    Invoke-Command -ComputerName $TargetIP -Credential $TargetCred -Authentication Negotiate -ScriptBlock {
                        param($tDom, $sDom, $tUser, $tPass, $sUser, $sPass)
                        $cmd = "netdom trust $tDom /domain:$sDom /SelectiveAUTH:yes /usero:`"$tUser`" /passwordo:`"$tPass`" /userd:`"$sUser`" /passwordd:`"$sPass`""
                        Start-Process "cmd.exe" "/c $cmd" -Wait -NoNewWindow | Out-Null
                    } -ArgumentList $TargetDomain, $SourceDomain, $TargetCred.UserName, $tgtPass, $SourceCred.UserName, $srcPass
                    Write-Host "    [+] Remediation executed on Target DC." -ForegroundColor Green
                }
            } else { Write-Warning "    [!] Trust not found on Target DC." }
        } catch { Write-Warning "    [!] Target check failed: $_" }

        Write-Host "`n=====================================================" -ForegroundColor Cyan
        Write-Host "[*] Automated Trust Setup Completed" -ForegroundColor Cyan
        Write-Host "=====================================================" -ForegroundColor Cyan
    }
}
