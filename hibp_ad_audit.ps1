[CmdletBinding()]
param(
    [string]$HIBPPath = "C:\HIBP\pwnedpasswords_ntlm.txt",
    [string]$OutDir   = "C:\HIBP\Reports"
)

Import-Module ActiveDirectory -ErrorAction Stop
Import-Module DSInternals     -ErrorAction Stop

New-Item -ItemType Directory -Force $OutDir | Out-Null

$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Log      = Join-Path $OutDir "hibp_ad_audit_$RunStamp.log"

Start-Transcript -Path $Log -Append
try {
    if (-not (Test-Path $HIBPPath)) { throw "HIBP file not found: $HIBPPath" }

    $NC = (Get-ADDomain).DistinguishedName
    $DC = [string]((Get-ADDomain).PDCEmulator)   # reliable in your environment

    Write-Host "DC:   $DC"
    Write-Host "NC:   $NC"
    Write-Host "HIBP: $HIBPPath"
    Write-Host ("HIBP bytes: " + (Get-Item $HIBPPath).Length)
    Write-Host ("Start: " + (Get-Date))

    $accounts = Get-ADReplAccount -All -Server $DC -NamingContext $NC
    Write-Host ("Accounts pulled: " + $accounts.Count)

    Write-Host ("Testing against HIBP. This may take a while and will not show progress. Status will update when finished. Start: " + (Get-Date))
    $result = $accounts | Test-PasswordQuality -WeakPasswordHashesFile $HIBPPath -IncludeDisabledAccounts
    Write-Host ("Test complete: " + (Get-Date))

    $hits = $result.WeakPassword
    $hitCount = if ($null -eq $hits) { 0 } else { $hits.Count }
    Write-Host ("HIBP matches: " + $hitCount)

    $hibpCsv = Join-Path $OutDir "ad_hibp_pwned_passwords_enriched_$RunStamp.csv"

    $enriched =
        $hits | ForEach-Object {
            $raw = [string]$_
            $sam = if ($raw -like "*\*") { $raw.Split('\')[-1] } else { $raw }

            # Skip computer accounts (machine passwords; not human-chosen)
            if ($sam.EndsWith('$')) { return }

            $ad = Get-ADUser -Identity $sam -Properties Enabled,PasswordLastSet,DistinguishedName,LastLogonDate,PasswordNeverExpires -ErrorAction SilentlyContinue

            if ($ad) {
                [pscustomobject]@{
                    Finding             = "HIBP_NTLM_MATCH"
                    Input               = $raw
                    Type                = "User"
                    SamAccountName      = $ad.SamAccountName
                    Enabled             = $ad.Enabled
                    PasswordLastSet     = $ad.PasswordLastSet
                    PasswordNeverExpires= $ad.PasswordNeverExpires
                    LastLogonDate       = $ad.LastLogonDate
                    DistinguishedName   = $ad.DistinguishedName
                }
            } else {
                [pscustomobject]@{
                    Finding             = "HIBP_NTLM_MATCH"
                    Input               = $raw
                    Type                = "NotFound"
                    SamAccountName      = $sam
                    Enabled             = $null
                    PasswordLastSet     = $null
                    PasswordNeverExpires= $null
                    LastLogonDate       = $null
                    DistinguishedName   = $null
                }
            }
        } | Sort-Object SamAccountName -Unique

    $enriched | Export-Csv $hibpCsv -NoTypeInformation
    Write-Host "Enriched report: $hibpCsv"

} finally {
    Stop-Transcript
}