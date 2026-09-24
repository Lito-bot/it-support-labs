<#
    Host-side helpers: drive the lab VMs through VirtualBox Guest Additions
    (VBoxManage guestcontrol), so every build step is a script, not a click.
#>
Set-StrictMode -Version Latest

$script:VBox     = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$script:GuestDir = 'C:\LabSetup'
$script:PSExe    = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'

function Invoke-VBox {
    # Plain $args (no param block) so guest-side switches like -NoProfile are
    # passed through untouched instead of being parsed as PowerShell parameters.
    $out = & $script:VBox @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "VBoxManage $($args[0..1] -join ' ') failed: $($out -join "`n")" }
    $out
}

function Copy-LabFilesToGuest {
    param([Parameter(Mandatory)][string]$VM, [Parameter(Mandatory)][string]$User,
          [Parameter(Mandatory)][string]$PasswordFile, [Parameter(Mandatory)][string]$Source)
    # copyto --recursive copies a folder's *contents*, so each folder gets its own target.
    foreach ($folder in 'setup', 'tools', 'data') {
        $target = "$script:GuestDir\$folder"
        Invoke-VBox guestcontrol $VM mkdir --username $User --passwordfile $PasswordFile --parents $target | Out-Null
        Invoke-VBox guestcontrol $VM copyto --username $User --passwordfile $PasswordFile --recursive `
            --target-directory $target "$Source\$folder" | Out-Null
    }
}

function Invoke-LabGuestScript {
    <# Runs a PowerShell script (path relative to C:\LabSetup) inside the VM and returns its output. #>
    param([Parameter(Mandatory)][string]$VM, [Parameter(Mandatory)][string]$User,
          [Parameter(Mandatory)][string]$PasswordFile, [Parameter(Mandatory)][string]$Script,
          [string[]]$ScriptArgs = @(), [int]$TimeoutMinutes = 30)
    # Parameter names (-Name) stay bare; values are single-quoted so spaces survive.
    $quotedArgs = ($ScriptArgs | ForEach-Object {
        if ($_ -match '^-[A-Za-z]\w*$') { $_ } else { "'" + ($_ -replace "'", "''") + "'" }
    }) -join ' '
    $command = "& '$script:GuestDir\$Script' $quotedArgs"
    Invoke-LabGuestCommand -VM $VM -User $User -PasswordFile $PasswordFile -Command $command -TimeoutMinutes $TimeoutMinutes
}

function Invoke-LabGuestCommand {
    <# Runs an inline PowerShell command inside the VM (for checks and evidence capture). #>
    param([Parameter(Mandatory)][string]$VM, [Parameter(Mandatory)][string]$User,
          [Parameter(Mandatory)][string]$PasswordFile, [Parameter(Mandatory)][string]$Command,
          [int]$TimeoutMinutes = 30)
    # The guest console defaults to IBM437, which mangles accented names in captured output.
    $full = "`$ErrorActionPreference = 'Stop'; [Console]::OutputEncoding = [Text.Encoding]::UTF8; $Command"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($full))
    Invoke-VBox guestcontrol $VM run --username $User --passwordfile $PasswordFile --timeout ($TimeoutMinutes * 60000) `
        --wait-stdout --wait-stderr --exe $script:PSExe '--' powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded
}

Export-ModuleMember -Function Copy-LabFilesToGuest, Invoke-LabGuestScript, Invoke-LabGuestCommand
