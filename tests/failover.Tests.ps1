BeforeAll {
    $Script = Join-Path $PSScriptRoot '..\failover.ps1'
    $PolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy'

    function New-Adapter($Name, $Media) {
        [pscustomobject]@{ Name = $Name; PhysicalMediaType = $Media; Status = 'Up'; LinkSpeed = '1 Gbps' }
    }
}

Describe 'failover.ps1' {
    BeforeDiscovery {
        $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    BeforeEach {
        # Nothing below may reach the real network stack, registry or UAC.
        $Adapters = @((New-Adapter 'Ethernet' '802.3'), (New-Adapter 'Wi-Fi' 'Native 802.11'))
        Mock Get-NetAdapter { $Adapters }
        Mock Get-NetIPInterface {
            [pscustomobject]@{ InterfaceAlias = 'Ethernet'; InterfaceMetric = 10; AutomaticMetric = 'Disabled' }
        }
        Mock Set-NetIPInterface { }
        Mock Find-NetRoute { [pscustomobject]@{ InterfaceAlias = 'Ethernet' } }
        Mock Get-ItemProperty { [pscustomobject]@{ fMinimizeConnections = 0 } }
        Mock New-Item { }
        Mock Set-ItemProperty { }
        Mock Remove-ItemProperty { }
        Mock Start-Process { }
    }

    Context 'status' {
        It 'finds the adapters by itself and reports the one carrying traffic' {
            $out = (& $Script status 6>&1 | Out-String)
            $out | Should -Match 'Wi-Fi stays connected alongside Ethernet'
            $out | Should -Match 'Internet traffic currently goes over: Ethernet'
        }

        It 'is the default action and changes nothing' {
            & $Script 6>&1 | Out-Null
            Should -Invoke Set-NetIPInterface -Times 0
            Should -Invoke Set-ItemProperty -Times 0
            Should -Invoke Remove-ItemProperty -Times 0
            Should -Invoke Start-Process -Times 0
        }

        It 'reports the Windows default when the policy is not set' {
            Mock Get-ItemProperty { $null }
            (& $Script status 6>&1 | Out-String) | Should -Match 'not set'
        }

        It 'asks for a name when there are two Ethernet adapters' {
            $Adapters = @((New-Adapter 'Ethernet' '802.3'), (New-Adapter 'Ethernet 3' '802.3'), (New-Adapter 'Wi-Fi' 'Native 802.11'))
            $out = (& $Script status 6>&1 | Out-String)
            $out | Should -Match "More than one Ethernet adapter found \('Ethernet', 'Ethernet 3'\)"
            $LASTEXITCODE | Should -Be 1
        }

        It 'says so when there is no Wi-Fi adapter' {
            $Adapters = @(New-Adapter 'Ethernet' '802.3')
            (& $Script status 6>&1 | Out-String) | Should -Match 'No Wi-Fi adapter found'
        }

        It 'uses the adapter names it is given' {
            $Adapters = @((New-Adapter 'Ethernet' '802.3'), (New-Adapter 'Ethernet 3' '802.3'), (New-Adapter 'Wi-Fi' 'Native 802.11'))
            & $Script status -EthernetAlias 'Ethernet 3' -WifiAlias 'Wi-Fi' 6>&1 | Out-Null
            Should -Invoke Get-NetIPInterface -ParameterFilter { $InterfaceAlias -contains 'Ethernet 3' }
        }
    }

    Context 'as administrator' -Skip:(-not $IsAdmin) {
        It 'enable sets the policy to 0 and pins both metrics' {
            & $Script enable 6>&1 | Out-Null
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Path -eq $PolicyKey -and $Name -eq 'fMinimizeConnections' -and $Value -eq 0
            }
            Should -Invoke Set-NetIPInterface -Times 1 -ParameterFilter { $InterfaceAlias -eq 'Ethernet' -and $InterfaceMetric -eq 10 }
            Should -Invoke Set-NetIPInterface -Times 1 -ParameterFilter { $InterfaceAlias -eq 'Wi-Fi' -and $InterfaceMetric -eq 50 }
            Should -Invoke Start-Process -Times 0
        }

        It 'enable takes custom metrics' {
            & $Script enable -EthernetMetric 5 -WifiMetric 80 6>&1 | Out-Null
            Should -Invoke Set-NetIPInterface -Times 1 -ParameterFilter { $InterfaceAlias -eq 'Ethernet' -and $InterfaceMetric -eq 5 }
            Should -Invoke Set-NetIPInterface -Times 1 -ParameterFilter { $InterfaceAlias -eq 'Wi-Fi' -and $InterfaceMetric -eq 80 }
        }

        It 'enable refuses an Ethernet metric that does not beat Wi-Fi' {
            $out = (& $Script enable -EthernetMetric 60 6>&1 | Out-String)
            $out | Should -Match 'EthernetMetric must be lower than WifiMetric'
            Should -Invoke Set-ItemProperty -Times 0
            Should -Invoke Set-NetIPInterface -Times 0
        }

        It 'disable removes the policy and returns to automatic metrics' {
            & $Script disable 6>&1 | Out-Null
            Should -Invoke Remove-ItemProperty -Times 1 -ParameterFilter { $Path -eq $PolicyKey -and $Name -eq 'fMinimizeConnections' }
            Should -Invoke Set-NetIPInterface -Times 1 -ParameterFilter {
                $InterfaceAlias -contains 'Ethernet' -and $InterfaceAlias -contains 'Wi-Fi' -and "$AutomaticMetric" -eq 'Enabled'
            }
        }
    }

    Context 'without administrator rights' -Skip:$IsAdmin {
        It 'enable relaunches itself elevated instead of changing anything' {
            & $Script enable 6>&1 | Out-Null
            Should -Invoke Start-Process -Times 1 -ParameterFilter { $Verb -eq 'RunAs' }
            Should -Invoke Set-ItemProperty -Times 0
            Should -Invoke Set-NetIPInterface -Times 0
        }
    }
}
