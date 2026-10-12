- **The mechanism-rules template carries the Windows and Linux/VLAN families of the network example.** (test: T0)
  Follow-up of a coherence scan on a Windows instance (2026-10-12), split agreed in the shared memory (item 7c):
  example rule 1 only knew macOS/BSD commands; `netsh`, the NetTCPIP cmdlets, iproute2 (also over ssh), nmcli,
  netplan and the Windows VLAN cmdlets passed unseen. Two example rules added to
  `templates/rules-instance/mechanism-rules.json` - data, not core rules; `ip addr show` and `Get-NetIPAddress` stay
  allowed. Checked the template's patterns against 10 commands (7 block, 3 pass).
