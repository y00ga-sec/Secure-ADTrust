function Set-ADTrust {
<#
.SYNOPSIS    
    Create a unidirectional outbound trust relationship between the current AD forest (trusting) and another (trusted)
    
.DESCRIPTION  
    Set up an Active Directory outbound trust to a remote forest. It will:

    - Add a conditional forwarder on this DC to the remote DC
    - Add a conditional forwarder on the remote DC to this DC
    - Create an outbound trust
    - Set trust to use Selective Authentication

.PARAMETER FQDN  
    FQDN of the remote DC

.PARAMETER IP  
    IP address of the remote DC
       
.PARAMETER Admin  
    Admin account of the remote DC in samAccountName form (i.e. DOMAIN\Administrator)

.PARAMETER TrustedDomain
    FQDN of the trusted domain (remote forest root domain)
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FQDN,

        [Parameter(Mandatory = $true)]
        [string]$IP,

        [Parameter(Mandatory = $true)]
        [string]$Admin,
                
        [Parameter(Mandatory = $true)]
        [string]$TrustedDomain
    )

    $DNSName = ($FQDN -split '\.')[1..($FQDN.Length - 1)] -join '.'

    Write-Host "[+] Adding conditional forwarder on this DC to the remote forest..." -ForegroundColor Cyan

    $existingForwarder = Get-DnsServerZone -Name $DNSName -ErrorAction SilentlyContinue
    if (!$existingForwarder) {
        try {
            Add-DnsServerConditionalForwarderZone -Name $DNSName -MasterServers $IP
            Write-Host "$DNSName has been added to conditional forwarders." -ForegroundColor Green
        } catch {
            Write-Warning "DNS conditional forwarder failed to add: $($_.Exception.Message)"
            return
        }
    } else {
        Write-Host "Conditional forwarder for $DNSName already exists. Skipping..." -ForegroundColor Yellow
    }

    Write-Host "[+] Adding conditional forwarder on the remote DC to this forest..." -ForegroundColor Cyan

    $RemoteCredential = Get-Credential -UserName $Admin -Message "Enter the password for $Admin"
    $localIP = (Test-Connection -ComputerName (hostname) -Count 1 | Select -ExpandProperty IPV4Address).IPAddressToString
    $localRootDomain = (Get-ADForest).RootDomain

    try {
        Invoke-Command -ComputerName $FQDN -Credential $RemoteCredential -ScriptBlock {
            Add-DnsServerConditionalForwarderZone -Name $using:localRootDomain -MasterServers $using:localIP
            Write-Host "Conditional forwarder to this domain has been successfully added on remote DC." -ForegroundColor Green
        }
    } catch {
        Write-Warning "Failed to add conditional forwarder on remote DC: $($_.Exception.Message)"
        return
    }

    Write-Host "[+] Creating outbound trust relationship..." -ForegroundColor Cyan

    $remoteContext = New-Object -TypeName "System.DirectoryServices.ActiveDirectory.DirectoryContext" -ArgumentList @("Forest", $DNSName, $RemoteCredential.UserName, $RemoteCredential.GetNetworkCredential().Password)
    $localForest = [System.DirectoryServices.ActiveDirectory.Forest]::getCurrentForest()

    try {
        $remoteForest = [System.DirectoryServices.ActiveDirectory.Forest]::getForest($remoteContext)
        Write-Host "$($remoteForest.Name) exists." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to retrieve remote forest info: $($_.Exception.Message)"
        return
    }

    try {
        $localForest.CreateTrustRelationship($remoteForest, "Outbound")
        Write-Host "Outbound trust has been created with forest $($remoteForest.Name)." -ForegroundColor Green
    } catch {
        Write-Warning "Could not create trust: $($_.Exception.Message)"
        return
    }

    # Get system UI language
    $language = (Get-Culture).Name

    # Determine localized value for "Yes", I ran into errors if the /SelectAUTH value was in the DC language, dunno why
    switch ($language) {
        'fr-FR' { $selectiveAuthValue = 'Oui' }
        'en-US' { $selectiveAuthValue = 'Yes' }
        'de-DE' { $selectiveAuthValue = 'Ja' }
        'es-ES' { $selectiveAuthValue = 'Sí' }
        default {
            Write-Warning "Unsupported language '$language'. Defaulting to 'Yes'. Make sure to check manually if Selective Authentication has been correctly configured by the script"
            $selectiveAuthValue = 'Yes'
        }
    }

    # Execute the command with the correct localized parameter
    Write-Host "[+] Setting trust to Selective Authentication..." -ForegroundColor Cyan
    try {
        netdom trust $env:USERDNSDOMAIN /Domain:$TrustedDomain /SelectiveAUTH:$selectiveAuthValue
        Write-Host "Trust set to use Selective Authentication." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to set Selective Authentication: $($_.Exception.Message)"
    }
}

function Grant-AllowedToAuthenticate {
<#
.SYNOPSIS
    Grants "Allowed to Authenticate" permission to a security principal on specific computer objects.

.PARAMETER ComputerName
    One or more computer names (sAMAccountName or DNS names) in the current domain.

.PARAMETER Principal
    The user or group from the trusted domain (e.g., "TRUSTEDDOM\User" or "TRUSTEDDOM\Domain Users") to be granted permission.

.EXAMPLE
    Grant-AllowedToAuthenticate -ComputerName "SRV01","SRV02" -Principal "TRUSTEDDOM\Domain Users"
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $true)]
        [string]$Principal
    )

    foreach ($name in $ComputerName) {
        try {
            $computer = Get-ADComputer -Identity $name -Properties DistinguishedName
            $dn = $computer.DistinguishedName
        } catch {
            Write-Warning "Computer '$name' not found in AD: $($_.Exception.Message)"
            continue
        }

        try {
            $acl = Get-Acl -Path "AD:$dn"
            $identity = New-Object System.Security.Principal.NTAccount($Principal)

            $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                $identity,
                [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
                [System.Security.AccessControl.AccessControlType]::Allow
            )

            $acl.AddAccessRule($ace)
            Set-Acl -Path "AD:$dn" -AclObject $acl

            Write-Host "Granted 'Allowed to Authenticate' to $Principal on $($computer.Name)" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to set permission on $($computer.Name): $($_.Exception.Message)"
        }
    }
}

