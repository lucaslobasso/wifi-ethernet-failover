# wifi-ethernet-failover

[![CI](https://github.com/lucaslobasso/wifi-ethernet-failover/actions/workflows/ci.yml/badge.svg)](https://github.com/lucaslobasso/wifi-ethernet-failover/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/lucaslobasso/wifi-ethernet-failover)](https://github.com/lucaslobasso/wifi-ethernet-failover/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-lightgrey.svg)](#requirements)

One PowerShell script that keeps Wi-Fi connected while an Ethernet cable is plugged in, so pulling the cable switches to Wi-Fi instantly instead of leaving the PC offline until a reboot.

- **For people who plug and unplug.** Wi-Fi day to day, cable for games or big downloads, no reboot in between.
- **Ethernet still wins.** While the cable is in, traffic goes over it; Wi-Fi just stays connected in the background.
- **Two settings, fully reversible.** One registry value and two interface metrics. `disable` puts Windows back exactly as it was.
- **Nothing installed.** No service, no scheduled task, nothing left running.

**[The problem](#the-problem) · [Requirements](#requirements) · [Install](#install) · [Settings](#settings) · [How it looks](#how-it-looks) · [Update](#update) · [How it works](#how-it-works) · [Troubleshooting](#troubleshooting) · [Uninstall](#uninstall)**

## The problem

Windows "minimizes simultaneous connections": about 40 seconds after an Ethernet link comes up, it disconnects Wi-Fi and switches off auto-connect on that adapter. On some machines auto-connect is not switched back on when the cable is unplugged, so Wi-Fi stays down until the next boot.

To check that this is what you have, open Event Viewer → Applications and Services Logs → Microsoft → Windows and look for these right after plugging the cable in:

| Log | Event | Text |
| --- | --- | --- |
| `Wcmsvc/Operational` | 1018 | Soft disconnect under thresholds for interface |
| `WLAN-AutoConfig/Operational` | 8003 | The network is disconnected due to a policy disabling auto connect on this interface |

## Requirements

- Windows 10 or 11, with one Ethernet and one Wi-Fi adapter.
- PowerShell: the Windows PowerShell 5.1 that ships with Windows, or PowerShell 7.
- Administrator rights for `enable` and `disable`. The script asks for them itself (a UAC prompt).

## Install

**One line** (PowerShell, no git needed):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/lucaslobasso/wifi-ethernet-failover/main/failover.ps1))) enable
```

That's it. No reboot is normally needed: Wi-Fi connects within a few seconds and stays connected. Read [`failover.ps1`](failover.ps1) first if you like; it's short.

To only look, without changing anything:

```powershell
irm https://raw.githubusercontent.com/lucaslobasso/wifi-ethernet-failover/main/failover.ps1 | iex
```

**From a clone:**

```powershell
git clone https://github.com/lucaslobasso/wifi-ethernet-failover
cd wifi-ethernet-failover
.\failover.ps1 enable
```

| Command | What it does | Needs admin |
| --- | --- | --- |
| `.\failover.ps1 status` (or no argument) | shows the policy, the metrics, both adapters and which one carries traffic | no |
| `.\failover.ps1 enable` | keeps Wi-Fi connected and prefers Ethernet when it is plugged in | yes |
| `.\failover.ps1 disable` | puts the Windows defaults back | yes |

## Settings

All optional. The adapters are found automatically; name them only when you have more than one of a kind.

| Parameter | Default | |
| --- | --- | --- |
| `-EthernetAlias` | auto | name of the Ethernet adapter, as shown by `Get-NetAdapter` |
| `-WifiAlias` | auto | name of the Wi-Fi adapter |
| `-EthernetMetric` | `10` | route priority of Ethernet. Lower wins, so it must be lower than `-WifiMetric` |
| `-WifiMetric` | `50` | route priority of Wi-Fi |

```powershell
.\failover.ps1 enable -EthernetAlias 'Ethernet 3' -WifiAlias 'Wi-Fi 2'
```

## How it looks

`.\failover.ps1 status` after `enable`, with the cable in:

```text
wifi-ethernet-failover 1.0.0
Policy fMinimizeConnections : 0 (Wi-Fi stays connected alongside Ethernet)

Name     Status LinkSpeed
----     ------ ---------
Ethernet Up     1 Gbps
Wi-Fi    Up     866.7 Mbps

InterfaceAlias InterfaceMetric AutomaticMetric
-------------- --------------- ---------------
Ethernet                    10        Disabled
Wi-Fi                       50        Disabled

Internet traffic currently goes over: Ethernet
```

Pull the cable and the last line changes to `Wi-Fi`.

## Update

Run the one-line install again, or `git pull` in a clone. The settings live in Windows, not in the script, so there is nothing to migrate. See [CHANGELOG.md](CHANGELOG.md).

## How it works

| Setting | `enable` | `disable` |
| --- | --- | --- |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy\fMinimizeConnections` | `0` | removed |
| Ethernet interface metric (IPv4 and IPv6) | `10` | automatic |
| Wi-Fi interface metric (IPv4 and IPv6) | `50` | automatic |

- The registry value is the Group Policy "Minimize the number of simultaneous connections to the Internet or a Windows Domain", set to *allow simultaneous connections*. Windows Home has no policy editor, but honors the value all the same. Windows picks the change up right away.
- With both adapters connected, Windows sends traffic over the one with the lowest metric. Automatic metrics usually favor Ethernet already; fixed ones make sure of it.
- Wi-Fi never disconnects, so there is nothing to reconnect when the cable goes: the Ethernet route disappears and the Wi-Fi route is already there.

## Troubleshooting

- **Wi-Fi is still disconnected after `enable`.** Connect to your network once by hand. If Windows drops it again within a minute, reboot once.
- **A game or call stayed on Wi-Fi after plugging the cable in.** Connections that are already open stay on the adapter they started on; only new ones use Ethernet. Plug in before you start.
- **Unplugging mid-game disconnected me.** Connections running over Ethernet end when the cable goes. Everything reconnects over Wi-Fi straight away, with no reboot.
- **"More than one Ethernet adapter found".** Name the ones to use with `-EthernetAlias` and `-WifiAlias` (see [Settings](#settings)). Virtual adapters (VPN, Hyper-V) are ignored automatically.
- **"Running scripts is disabled on this system".** Use the one-line install, or `powershell -ExecutionPolicy Bypass -File .\failover.ps1 enable`.
- **A work PC keeps undoing it.** A domain Group Policy may set the same value and overwrite yours. Ask your IT team.

## Uninstall

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/lucaslobasso/wifi-ethernet-failover/main/failover.ps1))) disable
```

From a clone: `.\failover.ps1 disable`. That removes the registry value and returns both adapters to automatic metrics. Nothing else was installed.

## Contributing

```powershell
Invoke-Pester tests                                                                        # Pester 5
Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1
```

The tests mock the network and registry cmdlets, so they change nothing on your machine. Keep the script compatible with Windows PowerShell 5.1.

## License

[MIT](LICENSE) © Lucas Lobasso
