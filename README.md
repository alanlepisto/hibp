# hibp

**Notice:**
**This repo is provided as-is to document and run the HIBP/AD password check.**

**AD Compromised Password Check (HIBP NTLM + DSInternals)**
Identify AD accounts whose current password hash matches the Have I Been Pwned (HIBP) NTLM compromised password corpus. Output is a single CSV report for remediation.
https://haveibeenpwned.com/

**What this does**
Pulls AD password hash data via DSInternals replication (Get-ADReplAccount) using the PDC Emulator.
Compares hashes to the offline HIBP Pwned Passwords NTLM corpus.
Produces one report with matched accounts with key AD attributes.

**What this does not do**
This is not a full password quality audit.
It does not reset passwords or change AD objects.
A match means the password hash appears in the HIBP corpus (HIBP_NTLM_MATCH).

**Requirements**

Domain joined server with adequate disk (HIBP corpus is large).

Run as Domain Admin either with the local user or via:
```powershell
$cred = Get-Credential "domain\adminaccount"
Start-Process powershell -Credential $cred -ArgumentList "-ExecutionPolicy RemoteSigned -File C:\HIBP\hibp_ad_audit.ps1" -WorkingDirectory "C:\HIBP"
```

**Components:**

RSAT “AD DS Tools” (ActiveDirectory module)

DSInternals PowerShell module installed
https://github.com/MichaelGrafnetter/DSInternals

.NET SDK installed (for the HIBP downloader tool)
https://dotnet.microsoft.com/en-us/download/dotnet/8.0

**Folder convention:**

Inputs: C:\HIBP\
Outputs: C:\HIBP\Reports\

**Step 1 — Install the HIBP downloader (one-time)**
The official downloader is the haveibeenpwned-downloader dotnet tool:
https://github.com/HaveIBeenPwned/PwnedPasswordsDownloader

```powershell
dotnet tool install --global haveibeenpwned-downloader
```

If the server can’t resolve the NuGet feed, add the source and retry:

```powershell
dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org
dotnet tool install --global haveibeenpwned-downloader
```

**Step 2 — Download the HIBP NTLM corpus (repeatable)**

From the target folder:

```powershell
New-Item -ItemType Directory -Force C:\HIBP | Out-Null
cd C:\HIBP
haveibeenpwned-downloader -n pwnedpasswords_ntlm
```

This creates:

`C:\HIBP\pwnedpasswords_ntlm.txt`

Sanity-check format (32 hex + : + count):

```powershell
Get-Content C:\HIBP\pwnedpasswords_ntlm.txt -TotalCount 3
```

**Step 3 — Install prerequisites for AD + DSInternals**
RSAT AD DS Tools (one-time)

```powershell
Install-WindowsFeature RSAT-ADDS -IncludeAllSubFeature -IncludeManagementTools
Install-Module DSInternals -Force
Import-Module DSInternals
```

Install-WindowsFeature is a Server Manager cmdlet and only exists on Windows Server. For Windows 10/11 workstations use the client equivalent:

**Option 1:** PowerShell (Windows 10/11)
```powershell
Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
```
**Option 2:** If that fails, use DISM
```powershell
DISM /Online /Add-Capability /CapabilityName:Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```
After it installs, verify the AD module loaded:
```powershell
Import-Module ActiveDirectory
Get-Module ActiveDirectory | Format-List Name, Version, Path
```

If Install-Module DSInternals fails, install from the official release ZIP:

https://github.com/MichaelGrafnetter/DSInternals/releases

**Update version if needed.**
```powershell
$zip  = "C:\HIBP\DSInternals_v6.4.zip"
$dest = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\DSInternals\6.4"
Unblock-File $zip
New-Item -ItemType Directory -Force $dest | Out-Null
Expand-Archive $zip -DestinationPath $dest -Force
Get-ChildItem $dest -Recurse -File | Unblock-File

Import-Module DSInternals -Force
Get-Module DSInternals | Format-List Name,Version,Path
```

If an error about PowerShell execution policy appears, such as "ModuleCompatibility.ps1 cannot be loaded because running scripts is disabled on this system." Run one of the following:

**Option 1:** Set execution policy for the current user (least invasive)
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

Then re-run your Import-Module DSInternals -Force line.

**Option 2:** Set it for the local machine (if running as admin)
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
```

If executing one of the above options, ensure that when the script is run that it's unblocked:
```powershell
Unblock-File C:\HIBP\hibp_ad_audit.ps1
```

**Step 4 — Run the audit script**

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\HIBP\hibp_ad_audit.ps1
```


**Outputs to C:\HIBP\Reports\**

hibp_ad_audit_<timestamp>.log (transcript)

ad_hibp_pwned_passwords_enriched_<timestamp>.csv

**Understanding the CSV**

Fields include:

Finding = HIBP_NTLM_MATCH

Input (object)

Type (of object)

SamAccountName

Enabled

PasswordLastSet

DistinguishedName

LastLogonDate (is based on replicated timestamp which is approximate)

PasswordNeverExpires

**Remediation guidance:**

Accounts in this report should have passwords reset per policy, with special handling for service accounts.
