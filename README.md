# Secure-ADTrust
Deploy Automatically Secure Active Directory Trust Relationships
---------

If you are interested in setting up Selective Authentication in your environment, please check [this blog post](https://publish.obsidian.md/yooga-sec/PERSO/PUBLISH/Article+perso/(Don't)+Trust+me+PART+II%2C+a+little+study+on+securing+Active+Directory+Trusts) I wrote first 😉 it summarizes prerequisites and walk through every steps of deploying an AD trust with Selective Authentication

This script offers two main functions that will help you :

- Deploy **Outbound External Trusts** with Selective Authentication
- Configure the **Allowed to authenticate** permissions to the right trusted objects in the trusting domain

## Set-ADTrust

This function will :

- Add a conditional forwarder on the current DC to the remote DC
- Add a conditional forwarder on the remote DC to the current DC
- Create an external outbound trust
- Set the trust to use Selective Authentication

You only need to provide the following parameters :

- FQDN of the remote DC
- IP address of the remote DC
- Admin account of for remote domain (i.e. DOMAIN\Administrator)
- FQDN of the trusted domain (remote forest root domain)

### Example usage :
````
Set-ADTrust -FQDN DC01.trusteddomain.local -IP 192.168.1.50 -Admin 'TRUSTED\DomainAdmin' -TrustedDomain trusteddomain.local
````

**Make sur the required ports are opened betweens both Domain Controllers and that both domains can resolve each other !**

https://github.com/user-attachments/assets/40d73d4d-9ec9-4c70-a79f-d3217947e1ce

## Grant-AllowedToAuthenticate

This function grants the "Allowed to Authenticate" permission to a trusted domain security principal on specific computer objects in the trusting domain.

You only need to provide the following parameters :

- One or more computer names (sAMAccountName or DNS names) in the current domain
- The user or group from the trusted domain (e.g., "TRUSTEDDOM\User" or "TRUSTEDDOM\Domain Users") to be granted permission

### Example usage :
````
Grant-AllowedToAuthenticate -ComputerName "SRV01","SRV02" -Principal "TRUSTEDDOM\Allowed_Auth_SRV01"
````

https://github.com/user-attachments/assets/861ffe9c-d2ca-4755-b6d4-42555122c4fe

-------------
## Greetings :

- lewill03 with [ADTrust.psm1](https://github.com/lewill03/ADTrust/blob/main/ADTrust.psm1)

