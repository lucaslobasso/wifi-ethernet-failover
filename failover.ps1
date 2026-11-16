<#
.SYNOPSIS
    Keeps Wi-Fi connected while Ethernet is plugged in, so unplugging the cable fails over instantly.

.DESCRIPTION
    By default Windows drops Wi-Fi shortly after an Ethernet link comes up and does not always bring it
    back when the cable is pulled. This script turns that behaviour off and pins interface metrics so
    Ethernet is still preferred whenever it is present.

    enable   Set fMinimizeConnections = 0 and pin metrics (Ethernet low, Wi-Fi high).
    disable  Remove the policy value and return both adapters to automatic metrics (Windows defaults).
    status   Show the current policy, metrics, adapter state and which adapter carries traffic.

    enable and disable need administrator rights; the script relaunches itself elevated if required.

.EXAMPLE
    .\failover.ps1 status
.EXAMPLE
    .\failover.ps1 enable
.EXAMPLE
    .\failover.ps1 enable -EthernetAlias 'Ethernet' -WifiAlias 'Wi-Fi' -EthernetMetric 10 -WifiMetric 50
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('enable', 'disable', 'status')]
    [string]$Action = 'status',

    # Adapter names. Auto-detected from the physical adapters when omitted.
    [string]$EthernetAlias,
    [string]$WifiAlias,

    [ValidateRange(1, 9999)][int]$EthernetMetric = 10,
    [ValidateRange(1, 9999)][int]$WifiMetric = 50,

    # Internal: set when the script relaunched itself elevated, so the window stays open.
    [switch]$Pause
)

$ErrorActionPreference = 'Stop'
$FailoverVersion = '1.0.0'
$SelfSource = $MyInvocation.MyCommand.ScriptBlock   # set when run as a script block (the one-line web install)
$PolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy'
$PolicyName = 'fMinimizeConnections'

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-Adapter([string]$MediaType, [string]$Label) {
    $found = @(Get-NetAdapter -Physical | Where-Object PhysicalMediaType -eq $MediaType)
    if ($found.Count -eq 0) { throw "No $Label adapter found. Pass its name explicitly." }
    if ($found.Count -gt 1) {
        $names = ($found.Name | ForEach-Object { "'$_'" }) -join ', '
        throw "More than one $Label adapter found ($names). Pass the one to use explicitly."
    }
    $found[0].Name
}

function Show-Status {
    $value = (Get-ItemProperty $PolicyKey -Name $PolicyName -ErrorAction SilentlyContinue).$PolicyName
    $policy = if ($null -eq $value) { 'not set (Windows default: drops Wi-Fi when Ethernet is up)' }
              elseif ($value -eq 0) { '0 (Wi-Fi stays connected alongside Ethernet)' }
              else { "$value (Windows drops Wi-Fi when Ethernet is up)" }
    "wifi-ethernet-failover $FailoverVersion"
    "Policy $PolicyName : $policy"

    Get-NetAdapter -Name $EthernetAlias, $WifiAlias |
        Format-Table Name, Status, LinkSpeed -AutoSize | Out-String | ForEach-Object TrimEnd
    Get-NetIPInterface -InterfaceAlias $EthernetAlias, $WifiAlias -AddressFamily IPv4 |
        Format-Table InterfaceAlias, InterfaceMetric, AutomaticMetric -AutoSize | Out-String | ForEach-Object TrimEnd

    $route = Find-NetRoute -RemoteIPAddress 1.1.1.1 -ErrorAction SilentlyContinue | Select-Object -First 1
    "`nInternet traffic currently goes over: $(if ($route) { $route.InterfaceAlias } else { 'nothing (no route)' })"
}

try {
    if (-not $EthernetAlias) { $EthernetAlias = Find-Adapter '802.3' 'Ethernet' }
    if (-not $WifiAlias) { $WifiAlias = Find-Adapter 'Native 802.11' 'Wi-Fi' }

    if ($Action -ne 'status' -and -not (Test-Admin)) {
        # Run straight from the web there is no file to relaunch, so save this script to one first.
        $selfPath = $PSCommandPath
        if (-not $selfPath) {
            if (-not $SelfSource) { throw 'Administrator rights needed. Run this again from an elevated PowerShell.' }
            $selfPath = Join-Path ([IO.Path]::GetTempPath()) 'wifi-ethernet-failover.ps1'
            Set-Content -LiteralPath $selfPath -Value $SelfSource.ToString() -Encoding UTF8
        }
        $shell = (Get-Process -Id $PID).Path
        $relaunch = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$selfPath`"", $Action,
            '-EthernetAlias', "`"$EthernetAlias`"", '-WifiAlias', "`"$WifiAlias`"",
            '-EthernetMetric', $EthernetMetric, '-WifiMetric', $WifiMetric, '-Pause'
        )
        'Administrator rights needed, relaunching elevated...'
        Start-Process $shell -Verb RunAs -ArgumentList $relaunch
        return
    }

    switch ($Action) {
        'enable' {
            if ($EthernetMetric -ge $WifiMetric) { throw 'EthernetMetric must be lower than WifiMetric.' }
            New-Item $PolicyKey -Force | Out-Null
            Set-ItemProperty $PolicyKey -Name $PolicyName -Value 0 -Type DWord
            Set-NetIPInterface -InterfaceAlias $EthernetAlias -InterfaceMetric $EthernetMetric
            Set-NetIPInterface -InterfaceAlias $WifiAlias -InterfaceMetric $WifiMetric
            "Enabled. If Wi-Fi does not connect by itself within a minute, connect it once by hand or reboot.`n"
        }
        'disable' {
            Remove-ItemProperty $PolicyKey -Name $PolicyName -ErrorAction SilentlyContinue
            Set-NetIPInterface -InterfaceAlias $EthernetAlias, $WifiAlias -AutomaticMetric Enabled
            "Disabled. Windows defaults restored.`n"
        }
    }
    Show-Status
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $failed = $true
}
finally {
    if ($Pause) { Read-Host "`nPress Enter to close" | Out-Null }
}
# Only set an exit code when run as a file: "exit" from the one-line web install would close the caller's shell.
if ($failed -and $PSCommandPath) { exit 1 }
