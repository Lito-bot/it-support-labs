<#
    Writes Group Policy Preferences drive mappings into a GPO.

    The GroupPolicy module has no cmdlet for GPP drive maps, so this writes the
    same Drives.xml the GPMC editor would, registers the Drive Maps client-side
    extension on the GPO and bumps the user version so clients pick it up.
#>
function Set-GppDriveMaps {
    param(
        [Parameter(Mandatory)]$Gpo,
        [Parameter(Mandatory)][hashtable[]]$Maps,
        [Parameter(Mandatory)][string]$FileServer,
        [Parameter(Mandatory)][string]$NetBIOSName
    )
    $domainDns = (Get-ADDomain).DNSRoot
    $gpoPath   = "\\$domainDns\SYSVOL\$domainDns\Policies\{$($Gpo.Id)}"
    $drivesDir = "$gpoPath\User\Preferences\Drives"
    New-Item -ItemType Directory -Path $drivesDir -Force | Out-Null

    $changed = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $items = foreach ($m in $Maps) {
        $sid = (Get-ADGroup $m.Group).SID.Value
        $uid = "{$([guid]::NewGuid().ToString().ToUpper())}"
        @"
  <Drive clsid="{935D1B74-9CB8-4e3c-9914-7DD559B7A417}" name="$($m.Letter):" status="$($m.Letter):" image="2" changed="$changed" uid="$uid" bypassErrors="1">
    <Properties action="U" thisDrive="NOCHANGE" allDrives="NOCHANGE" userName="" path="\\$FileServer\$($m.Share)" label="$($m.Share)" persistent="1" useLetter="1" letter="$($m.Letter)"/>
    <Filters><FilterGroup bool="AND" not="0" name="$NetBIOSName\$($m.Group)" sid="$sid" userContext="1" primaryGroup="0" localGroup="0"/></Filters>
  </Drive>
"@
    }
    $xml = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`r`n<Drives clsid=`"{8FDDCC1A-0C3C-43cd-A6B4-71A6DF20DA8C}`">`r`n$($items -join "`r`n")`r`n</Drives>"
    [IO.File]::WriteAllText("$drivesDir\Drives.xml", $xml, (New-Object Text.UTF8Encoding($true)))

    # Register the Drive Maps CSE so clients know this GPO has preferences to apply.
    $gpoDN = "CN={$($Gpo.Id)},CN=Policies,CN=System,$((Get-ADDomain).DistinguishedName)"
    $cse = '[{00000000-0000-0000-0000-000000000000}{2EA1A81B-48E5-45E9-8BB7-A6E3AC170006}][{5794DAFD-BE60-433F-88A2-1A31939AC01F}{2EA1A81B-48E5-45E9-8BB7-A6E3AC170006}]'
    $obj = Get-ADObject $gpoDN -Properties versionNumber
    # versionNumber packs user version in the high 16 bits, computer in the low 16.
    $newVersion = [int]$obj.versionNumber + 65536
    Set-ADObject $gpoDN -Replace @{ gPCUserExtensionNames = $cse; versionNumber = $newVersion }

    $gptIni = "$gpoPath\GPT.INI"
    $content = if (Test-Path $gptIni) { Get-Content $gptIni } else { @('[General]') }
    $content = @($content | Where-Object { $_ -notmatch '^Version=' }) + "Version=$newVersion"
    Set-Content -Path $gptIni -Value $content -Encoding ASCII
}
