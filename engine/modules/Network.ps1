# ==============================================================
#  Network reset
#  Rewrite of pulizia_connessione.bat.
#  Changes: only touches DHCP adapters (release on a static IP just
#  errors), checks connectivity afterwards, optional deep reset
#  (Winsock + TCP/IP stack) for real connection problems.
# ==============================================================

function Invoke-NetworkReset {
    Write-Head 'Network refresh'
    Write-Warn 'Your connection will drop for a few seconds (do not run this mid-match).'

    [void](Invoke-Native -Description 'DNS cache flushed' -File 'ipconfig.exe' -Arguments @('/flushdns'))
    [void](Invoke-Native -Description 'ARP cache cleared' -File 'netsh.exe' -Arguments @('interface','ip','delete','arpcache'))

    $dhcp = @(Invoke-WithTimeout -Seconds 20 -What 'DHCP adapters' -Script {
        Get-NetIPInterface -AddressFamily IPv4 -Dhcp Enabled -ConnectionState Connected -ErrorAction Stop |
            Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|VirtualBox|VMware|Hyper-V' } |
            ForEach-Object { [pscustomobject]@{ InterfaceAlias = $_.InterfaceAlias } }
    } | Where-Object { $_ })
    if ($dhcp.Count -eq 0) {
        Write-Skip 'No DHCP adapter connected - IP release/renew skipped (static IP)'
    } else {
        foreach ($i in $dhcp) {
            $alias = $i.InterfaceAlias
            [void](Invoke-Native -Description "IP released: $alias" -File 'ipconfig.exe' -Arguments @('/release', $alias))
            [void](Invoke-Native -Description "IP renewed: $alias"  -File 'ipconfig.exe' -Arguments @('/renew', $alias))
        }
    }
    [void](Invoke-Native -Description 'DNS registration refreshed' -File 'ipconfig.exe' -Arguments @('/registerdns'))

    if (-not $script:DryRun) {
        Start-Sleep -Seconds 3
        $ok = Test-Connection -ComputerName 1.1.1.1 -Count 2 -Quiet -ErrorAction SilentlyContinue
        if ($ok) { Write-OK 'Internet reachable' } else { Write-Warn 'No reply from 1.1.1.1 yet - give it a few seconds or reboot' }
    }

}

function Invoke-DeepNetworkReset {
    Write-Head 'Deep network reset (Winsock + TCP/IP stack)'
    Write-Info 'Only needed for real connection problems (no internet, DNS errors, broken VPN leftovers).'
    Write-Warn 'Clears custom DNS / static IP settings - note them down first. Reboot required.'
    if (-not (Confirm-Action 'Reset the network stack?' -DefaultNo)) { return }
    [void](Invoke-Native -Description 'Winsock catalog reset' -File 'netsh.exe' -Arguments @('winsock','reset'))
    [void](Invoke-Native -Description 'TCP/IP stack reset'   -File 'netsh.exe' -Arguments @('int','ip','reset') -OkCodes @(0,1))
    $script:RebootNeeded = $true
}
