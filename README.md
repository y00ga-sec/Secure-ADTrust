# SecureAD-Trust

A PowerShell automation script (`SecureAD-Trust.ps1`) designed to seamlessly establish and configure Active Directory Trusts (BiDirectional, Inbound, or Outbound) between two distinct domains. You can check [my article about securing AD trusts](https://blog.y00ga.lol/PERSO/PUBLISH/Article+perso/(Don't)+Trust+me+PART+II%2C+a+little+study+on+securing+Active+Directory+Trusts)

This script acts as a powerful wrapper around the legacy `netdom.exe` utility, bypassing common PowerShell parsing errors by executing raw commands securely. It fully automates the prerequisites, the trust creation, the application of Selective Authentication, and performs end-to-end verification.



## ✨ Features

* **Directional Control:** Choose between `BiDirectional` (default), `Inbound` (Target trusts Source), or `Outbound` (Source trusts Target) relationships.
* **Automated DNS Configuration:** Automatically creates DNS Conditional Forwarders on both the Source and Target Domain Controllers.
* **WinRM Readiness:** Dynamically adds the respective Domain Controllers to each other's WinRM `TrustedHosts` list to allow cross-domain remote management.
* **Bulletproof Execution:** Uses `cmd.exe /c` to strictly control argument quoting, preventing PowerShell from breaking complex `netdom` credential strings.
* **Smart Selective Authentication:** Can optionally enforce Selective Authentication. The script intelligently applies it only to the *Trusting* domain(s) based on the chosen direction.
* **Self-Healing Verification:** Validates the trust direction and Selective Authentication status on both DCs using `Get-ADTrust`. If requested but missing, it automatically triggers a remediation sequence.

## 📋 Prerequisites

Before running this script, ensure the following requirements are met:
1.  **Network Connectivity:** The Source and Target DCs must be able to route to each other over standard AD ports (DNS: 53, Kerberos: 88, LDAP: 389/636, SMB: 445, RPC, WinRM: 5985/5986).
2.  **Credentials:** You must have valid **Domain Admin** credentials for *both* the Source and Target domains.
3.  **Active Directory Module:** The RSAT Active Directory module must be available (specifically for the `Get-ADTrust` cmdlet).
4.  **Execution Policy:** Ensure your execution policy allows running custom scripts (`Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`).

## 🚀 Usage & All Use Cases

First, dot-source the script to load the `Set-ADtrust` function into your current PowerShell session:

```powershell
. .\SecureAD-Trust.ps1
```

🔹 Preparation: Gather Credentials
For all the use cases below, retrieve administrative credentials for both domains into variables:

```powershell
$SourceCred = Get-Credential -UserName "administrator@source.local" -Message "Source Domain Admin"
$TargetCred = Get-Credential -UserName "administrator@target.local" -Message "Target Domain Admin"
```


- Use Case 1: BiDirectional Trust (Standard / Forest-Wide Auth)
Scenario: Both domains trust each other equally. Users from either domain can access resources in the other domain (subject to standard ACLs).

```powershell
Set-ADtrust -SourceDC "DC01.source.local" `
            -SourceDomain "source.local" `
            -SourceCred $SourceCred `
            -TargetDC "DC01.target.local" `
            -TargetDomain "target.local" `
            -TargetCred $TargetCred `
            -Direction BiDirectional
(Note: BiDirectional is the default behavior if the -Direction parameter is omitted).
```

- Use Case 2 : Outbound Trust (One-Way)
Scenario: The Source domain trusts the Target domain.

Result: Users in the Target domain can access resources in the Source domain. Users in the Source domain cannot access resources in the Target domain.

```powershell
Set-ADtrust -SourceDC "DC01.source.local" `
            -SourceDomain "source.local" `
            -SourceCred $SourceCred `
            -TargetDC "DC01.target.local" `
            -TargetDomain "target.local" `
            -TargetCred $TargetCred `
            -Direction Outbound

```

- Use Case 3: Inbound Trust (One-Way)
Scenario: The Target domain trusts the Source domain.

Result: Users in the Source domain can access resources in the Target domain. Users in the Target domain cannot access resources in the Source domain.

```powershell
Set-ADtrust -SourceDC "DC01.source.local" `
            -SourceDomain "source.local" `
            -SourceCred $SourceCred `
            -TargetDC "DC01.target.local" `
            -TargetDomain "target.local" `
            -TargetCred $TargetCred `
            -Direction Inbound

```

The `-SelectiveAuthentication` parameter will set up the selected type of trust with Selective Auth, which will need to be manually completed by giving the `Allowed to authenticate` ACE on the required objects, to the principals in the other domain you want to give access
