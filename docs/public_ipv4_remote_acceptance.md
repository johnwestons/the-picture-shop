# Public IPv4 remote acceptance test

This is a one-time engineering test for The Picture Shop's free, direct multiplayer path. It does not use a relay, matchmaking service, telemetry service, manual port forward, or router DMZ. The host requests one temporary UDP mapping with a two-minute lease through PCP, NAT-PMP, or UPnP IGD in that order, and the guest proves that the encrypted game transport works from a different Internet connection.

This is not a production release gate by itself. Passing it gives us the missing physical-network evidence for automatic public-IPv4 hosting. Carrier-grade NAT cannot be bypassed by this test; direct IPv6 remains the free no-relay route on those networks.

## What you need

- Two Windows 10 or 11 x64 PCs on different Internet connections.
- Your brother's PC connected to the Wi-Fi network being tested. That PC is the **Host**.
- Your PC on your own home Internet, a phone hotspot, or another genuinely separate connection. Your PC is the **Guest**.
- Administrator permission on the Host PC. The Guest does not need administrator permission.
- Access to the router's normal status page only to read its **Internet/WAN IPv4 address**. Do not change router settings.
- A private voice, text, or screen-sharing call. The call may use its normal service, but do not use a VPN, mesh-VPN, remote-access tunnel, or “same LAN” feature between the two PCs.

You do not need to take your PC to your brother's house. In fact, the two PCs must remain on different Internet connections for this test to prove anything.

## Before starting

1. Send the ZIP privately to your brother. For every attempt, both of you must extract a fresh copy into a new, empty local folder; do not run it from inside the ZIP or reuse a folder from an earlier attempt.
2. Your brother uses only the **Host** folder. You use only the **Guest** folder.
3. Close any VPN or mesh-network app on both PCs for the test. Ordinary screen sharing is fine when it does not install or enable a network tunnel.
4. Leave Windows Firewall enabled. Do not create a port forward, enable DMZ, enable a broad LÖVE firewall rule, or change the router's UPnP/PCP/NAT-PMP settings.

### Optional IPv6-first check

On each PC, double-click **Check IPv6 Readiness.bat**. This sends no traffic and retains no address. If both PCs report `TPS_IPV6_LOCAL_READINESS=PASS`, both local networks have a global IPv6 address and default route; that makes IPv6 the preferred candidate. `INBOUND_REACHABILITY_PROVEN=False` is expected because only a real encrypted connection between the two networks can prove that their firewalls permit Direct hosting. A failure on either PC does not block this IPv4 test.

## Confirm that the router has public IPv4

On your brother's router status page, find the Internet/WAN **IPv4** address. Stop if it is absent or begins with any of these ranges:

- `10.`
- `100.64.` through `100.127.` (carrier-grade NAT)
- `127.`
- `169.254.`
- `172.16.` through `172.31.`
- `192.168.`

Also stop if the displayed address is `0.0.0.0`, begins `224.` or higher, or the router says DS-Lite, MAP-T, IPv4 over IPv6, or carrier-grade NAT. Do not paste or send the WAN address to anyone. The probe will independently reject a non-public mapped endpoint.

## Run the test

1. On the Host PC, double-click **Start Host Preflight.bat**. This performs local checks only. It sends no router packet, creates no mapping, and makes no firewall change. If Windows Defender Firewall asks whether to allow `lovec.exe`, choose **Cancel**; the mapping launcher creates its own exact temporary rule later. Continue only if the terminal shows `TPS_PUBLIC_IPV4_PREFLIGHT=PASS` and `NETWORK_TRAFFIC_SENT=False`. The firewall audit is intentionally deferred to the administrator-approved mapping launcher because some Windows versions deny firewall inspection to a standard process.
2. On the Guest PC, double-click **Start Guest.bat**. Leave the invitation window open.
3. On the Host PC, double-click **Start Host Mapping Test.bat**. Accept the Windows administrator prompt. The administrator PowerShell window intentionally remains open so success or failure cannot disappear; close it only after recording the final result.
4. The Host terminal asks for two exact confirmations. After checking the router status page, type `PUBLIC IPV4 CONFIRMED`. Then type `MAP` to authorize one temporary two-minute mapping. Continue only when the administrator window reports `BROAD_PROBE_FIREWALL_RULE_ABSENT=True` and `TEMPORARY_FIREWALL_RULE_ACTIVE=True`.
5. When the Host window says the mapping is ready, press **C**. Send the copied invitation privately to the Guest. Do not post it publicly or include it in a screenshot.
6. Paste the invitation into the Guest window and press **Enter**.
7. Keep both windows open. On a router that ignores PCP and NAT-PMP, reaching UPnP can take about five minutes because possible mappings are never overlapped. Once an invitation appears, the probe authenticates the remote guest, checks all three encrypted game channels, waits for one real lease renewal, checks all three channels again, closes the listener, and asks the router to delete the mapping. This normally takes a little over one minute after connection.
8. A complete pass requires both:
   - Host result: `TPS_PUBLIC_IPV4_HOST=PASS`, `LEASE_RENEWED=True`, `LISTENER_CLOSED_BEFORE_DELETE=True`, and `DELETION_ACKNOWLEDGED=True`.
   - Guest result: `TPS_PUBLIC_IPV4_GUEST=PASS` and both three-channel markers are `True`.
9. The Host terminal must finally show `TEMPORARY_FIREWALL_RULE_REMOVED=True`.

The safe result files are `last-host-result.txt` and `last-guest-result.txt` inside the corresponding folders. They contain pass/fail markers only—no invitation, IP address, gateway, Wi-Fi name, or router details. Those two files are safe to send back for review.

## Validate the returned result pair

Keep the original ZIP and `build-report.txt` in `output/public-ipv4-probe`. From the repository root, run:

```powershell
.\tools\verify_public_ipv4_remote_results.ps1 -HostResult "PATH_TO_HOST_RESULT" -GuestResult "PATH_TO_GUEST_RESULT"
```

The checker strictly verifies both result schemas, the frozen ZIP SHA-256, the build report, cleanup markers, and the allowed redacted failure reasons. It writes a combined privacy-safe report to `output/public-ipv4-results/verified-remote-result.json` without copying input paths, addresses, invitations, player names, or raw logs.

The frozen result format does not contain a kit ID or run ID, so the report records that provenance limitation instead of claiming cryptographic proof it cannot establish. Exact pass files are identical across runs. Full acceptance therefore requires two operator confirmations: both files were collected immediately from the same fresh-extraction attempt, and the Host terminal showed `TEMPORARY_FIREWALL_RULE_REMOVED=True`. After confirming both, rerun the command with `-SameAttemptConfirmed -FirewallCleanupConfirmed`.

Exit code `0` means the two result files are canonical and both probes passed; it is not a complete acceptance gate unless the output also says `ACCEPTANCE_GATE=PASS`. Exit code `1` means the returned files are canonical but the remote test failed. Exit code `2` means the evidence is missing, altered, unsafe, or internally inconsistent.

## If anything is interrupted

1. Close the probe windows.
2. On the Host PC, double-click **Cleanup Host Firewall Rule.bat**, accept the administrator prompt, and type `CLEANUP`. It removes only the kit's exact owned firewall rule.
3. Leave the router alone. Any mapping that did not receive a deletion acknowledgement has a finite lease and expires within two minutes of its last successful creation or renewal.
4. Do not “fix” a failure by disabling Windows Firewall, adding a manual port forward, using DMZ, turning on a VPN tunnel, or broadening the firewall rule.

If preflight or the test fails after creating new safe result files, send only those new files and describe which numbered step was on screen. A launcher-level failure may create no new result; in that case, send no old result and no raw log. Start any retry from another fresh extraction. A failure is useful evidence: it may mean the router lacks PCP/NAT-PMP, the network is double-NAT/CGNAT, the default route changed, or direct UDP is filtered.

If the launcher says Windows has a broad rule for the exact test executable, close that attempt and delete its extracted test folder. Extract the ZIP into a different new folder, run preflight again, and choose **Cancel** if Windows asks to allow `lovec.exe`. Do not disable Windows Firewall or delete an unrelated rule. Once the old extracted executable is gone, its path-specific rule cannot expose a listener.

If **Allow access** was selected accidentally, close the test and do not start the mapping. From a fresh copy of the Host folder, double-click **Remove Accidental Test Firewall Rules.bat**, accept the administrator prompt, and type `REMOVE ACCIDENTAL TEST RULES`. The guarded cleanup removes only Windows-generated broad TCP/UDP rules whose executable path identifies this exact public-IPv4 test kit; it does not remove installed LÖVE rules, unrelated application rules, or the kit's owned exact temporary rule. Continue only when it reports `ACCIDENTAL_TEST_FIREWALL_RULES_ABSENT=True`, then use another fresh extraction for the retry.

## Diagnose a confirmed mapping timeout

Run this only after the ordinary Host test returns `REASON=mapping_timeout` and the router, Host PC, and Wi-Fi connection have not changed. The Guest PC is not needed for this diagnostic.

1. Extract a fresh copy of the updated ZIP into a new, empty local folder on the same Host PC.
2. In the Host folder, double-click **Start Host Mapping Traffic Check.bat** and accept the administrator prompt.
3. Type `PUBLIC IPV4 CONFIRMED`, then type `MAP`. This authorizes the same temporary two-minute PCP/NAT-PMP mapping attempt. If a mapping unexpectedly succeeds, diagnostic mode immediately closes the listener and deletes the mapping; it never waits for a guest invitation.
4. Keep the administrator window open. A no-response run normally takes about five minutes because the adapter safely serializes PCP, NAT-PMP, and UPnP and honors the finite-lease cleanup boundary.
5. Continue only when the final markers include `PKTMON_STOPPED=True`, `PKTMON_FILTER_REMOVED=True`, and `TEMPORARY_FIREWALL_RULE_REMOVED=True`.
6. Send back only `last-mapping-traffic-result.txt`. It contains booleans and a safe mapping outcome only—no address, adapter name, gateway, Wi-Fi name, packet bytes, or payload.

The diagnostic uses Windows Packet Monitor in counters-only mode with one IPv4/UDP/5351 filter across network adapters. It does not enable packet logging or create an ETL/PCAP file.

- `UDP_5351_NIC_TX_OBSERVED=True` and `UDP_5351_NIC_RX_OBSERVED=False` means a mapping request reached a network adapter but no matching UDP reply returned. On an unchanged network, proceed to the exact-network-bound UPnP IGD fallback rather than changing the PCP/NAT-PMP serializer.
- Both markers `True` means a matching reply reached a network adapter; inspect the exact-socket receive and response-validation path before adding another protocol.
- `UDP_5351_NIC_TX_OBSERVED=False` means the expected request was not observed at a network adapter; inspect the exact socket/send path first.

The filter is removed automatically. If either Packet Monitor cleanup marker is `False`, double-click **Cleanup Mapping Traffic Check.bat** in that same Host folder and type the exact confirmation it displays. The cleanup refuses to remove anything unless Packet Monitor contains only the test's exact IPv4/UDP/5351 filter.
