# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-16

### Added
- `failover.ps1` with `status`, `enable` and `disable`: keeps Wi-Fi connected while Ethernet is plugged in (`fMinimizeConnections = 0`) and pins interface metrics so Ethernet is preferred.
- Adapters are detected automatically; `-EthernetAlias`, `-WifiAlias`, `-EthernetMetric` and `-WifiMetric` override.
- Asks for administrator rights by itself, also when run in one line straight from the web.
- Pester tests and CI on PowerShell 7 and Windows PowerShell 5.1.
