# wifi-ethernet-failover

One script, `failover.ps1` (`status` | `enable` | `disable`): sets the WcmSvc policy `fMinimizeConnections = 0` and pins
interface metrics so Wi-Fi stays connected next to Ethernet. No installer, nothing left running.

- Check: `Invoke-Pester tests` (Pester 5) and `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1`.
- Tests mock every network, registry and `Start-Process` call; keep it that way so they never touch the machine or
  raise a UAC prompt. Any new cmdlet that changes state needs a mock in `BeforeEach`.
- Must stay compatible with Windows PowerShell 5.1 (CI runs both).
- The README documents running it as a script block (`& ([scriptblock]::Create((irm ...))) enable`). In that mode
  `$PSCommandPath` is empty: elevation saves the script to %TEMP% first, and the script must not call `exit`.
- Running `enable`/`disable` on the dev machine changes the real network settings.
- Version: `$FailoverVersion` in failover.ps1 + CHANGELOG + the sample output in the README.
- README follows the layout of the owner's other public tools: badges, pitch, nav, Requirements, Install, Settings,
  How it looks, Update, How it works, Troubleshooting, Uninstall, Contributing, License.
