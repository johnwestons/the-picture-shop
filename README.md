# The Picture Shop

The always-available **OPTIONS** button (or `O` / controller Start) opens game,
audio, movable touch-control, and developer cheat settings. In **CONTROLS**, drag
the movement stick and action buttons in the preview; positions are saved for
the device and applied immediately. **CHEATS** can safely edit cash and common
inventory/progression values in the live host shop or any offline save slot.

A playable LÖVE 2D vertical slice for an isometric pixel-art print-shop management game.

## Playable warehouse storage slice

On the office computer's **Warehouse** page, buy **left storage** ($4,500).
The raccoon calls, arrives through the front entrance and builds over four full
game days. Buy the **forklift** ($6,500) to use all ten shelf slots.
Near it, use **V** to drive/park, **E** to pick up/drop, **G** to lower,
**T** for travel height and **R** to raise. Stop before lifting; drive with cargo
at travel height. Near the rack, **H** opens shelves; inside, **U** raises the
forks while **R** retains Retrieve. On-screen buttons provide touch equivalents.
At full height, **K / STACK / TAKE TOP** builds or dismantles two-high piles of
matching-footprint customer paper skids. The supporting skid cannot be moved
until its upper pallet is removed.

The taller upper warehouse walls are now registered in-game, keeping the lower
upgrade gaps and all existing actor/equipment sizes. Construction uses concrete,
hammer, drill and paint-roller work loops. This is still a development slice
with provisional art: only left storage and the forklift are available; the
complete floor/front-edge remake, other room choices and final vehicle/module
polish are not finished.
See [current status and verification](docs/warehouse_build_status.md).

## Run on Windows

1. Install [LÖVE 11.x](https://love2d.org/) with the 64-bit Windows installer.
2. Double-click `RUN_GAME.bat` in this folder.

The launcher finds LÖVE on `PATH`, in a local `runtime` folder, or in the normal Program Files locations. LÖVE must receive the whole project folder; do not open `main.lua` by itself.

Tester installers are built with `tools/build_windows_installer.ps1`. The resulting per-user
`ThePictureShop-Windows-Setup-<version>.exe` under `output/windows` contains a fused x64 game executable
and the LÖVE runtime, smoke-tests the packaged executable before compilation, preserves saves during
uninstall, and does not create a firewall rule. Private unsigned builds may trigger a Windows reputation
warning; public releases should be code-signed.

## Run on Android

For a phone-shareable private test installer, double-click `PACK_ANDROID.bat`.
It advances the Android version, runs desktop and packaged-mobile checks, verifies
the APK and its signing key against the previous build, and creates a numbered
folder in `output/android-share` containing the `.apk` installer and instructions.
Open that folder in OneDrive on your phone and download the APK to share it.
If your messaging app rejects APK attachments or the file size, text a OneDrive
download link instead. Opening the APK on Android starts the system installer.
Installing over the old app keeps saves; uninstalling the old app first clears
its test saves. This private packaging command does not replace the release gate
or physical-device multiplayer acceptance.

The Android edition is built from this same Lua source tree; there is no copied mobile gameplay fork.
With one USB-debugging-enabled phone connected, run `./BUILD_ANDROID.ps1 -Install` in PowerShell.
The command packages the current game, runs the smoke suite, builds and verifies a signed development
APK, installs it without deleting existing saves, launches it, and verifies the Picture Shop startup marker.
Use `./BUILD_ANDROID.ps1 -PackageOnly` when only the testable `.love` archive is needed. See
`ANDROID_PORT.md` for the phone, controller, build, and release checklist.

## Local multiplayer

Choose a writable save, then use **LOCAL PLAY > HOST THIS SHOP** on Windows or Android. Up to three
Windows/Android workers can join the host's displayed IPv4 address over normal Wi-Fi or a compatible
phone hotspot. The host alone owns and saves the shop; guests receive the live shop and can move,
operate the dock door, talk to clients, use the office computer and skid wrapper, inspect pallet work
orders read-only, run the Polar cutter's production and safety controls, and share the host-authoritative
pallet jack. They can also operate the complete Windmill console: plate preparation, six host-scored setup
checks, proof approval, production, cleanup, maintenance, and technician booking. Guests can now also inspect
the host's live supplier catalog and request stock or used-machine purchases; only the host validates cash,
availability, and the resulting save. Guest Workers can also open a parked box truck, review a paged
host-owned manifest, unload customer/supplier/machine deliveries, load finished pickups, and release the
empty truck. The remote cutter now includes host-owned lockout, lubrication and gearbox checks, blade
removal/sleeving, and blade-technician scheduling; guests submit bounded control choices while only the
host consumes kits or saves results. The remote wrapper now includes its full four-component service
sequence with host-scored misses, repair quality, exact-once kit consumption, and disconnect rollback.
Protocol v19 keeps a full four-device
session within the 1,200-byte realtime packet ceiling: a reliable welcome contains the host and the
newly assigned worker, then fixed 12 Hz motion arrives as MTU-safe one-player shards that each client
merges by player ID. A Guest Worker holding the pallet-jack lease can now attach, move, turn, and place
the cutter, skid wrapper, or Windmill using a bounded machine choice and grid-cell token. The same
authoritative tick carries the live and terminal poses of the relocated
cutter, skid wrapper, or Windmill, so every worker sees the machine remain mounted while it moves.
The host validates machine readiness, console occupancy, range, and floor clearance; disconnect recovery
locks the machine safely before releasing the jack. The cutter uses its own 12 Hz bounded
runtime stream, an exclusive host lease, host-validated setup/cut commands, either-button multiplayer cutting,
an urgent E-STOP/barrier lane,
and safe disconnect/revision recovery. The Windmill has the same exclusive lease and its own 12 Hz bounded
runtime stream; plate timing and setup scores are calculated only by the host, and urgent E-STOP is serviced
before another sheet advances. Guests now use the host GUI renderers for the cutter and its service
screens, wrapper, all Windmill pages, CritterNet computer, reception, vendor, truck manifest, and wall
phone. Typed estimates, promotions, shopping-cart checkout, machine sales, bill payments, and phone
actions are bounded requests executed and saved only by the host. The phone has an exclusive lease
and stale-call protection. This v16 source-only update passes 2,285 desktop and 2,285 forced-mobile
checks, including full guest cutting and two-color printing jobs with repeated requests, reconnect,
wrapping and payment. Feeder setup controls now pass the network allowlist. No connected devices were
used or updated. All devices need a matching new build before the next
physical test. See `docs/lan_multiplayer_slice.md` for the supported protocol-v16
scope and `docs/lan_multiplayer_device_test.md` for the physical-device matrix.

The protocol-v7 / Android `.11` targeted four-device pass completed on August 28, 2026: an SM-S938U
Android host, two Android workers, and a Windows worker reached `4/4 WORKERS`, passed independent
movement and live cutter/wrapper/Windmill observation, and returned cleanly to `4/4` after the SM-J410G
left and rejoined. The broader 15-minute, hotspot, and offline-reload checks remain unclaimed.

The protocol-v8 / Android `.13` targeted cutter pass completed on August 29, 2026: an SM-S938U Android
host, an SM-J410G worker, and a Windows worker reached `3/4 WORKERS` and passed the full remote cutter
workflow, host and guest one-button cuts, two-worker contention, urgent E-STOP, disconnect/reacquire,
and clean rejoin. It also fixed and physically verified the carried-pallet/background-overlay crash found
in `.12`. A fourth device, the 15-minute soak, hotspot coverage, and the final offline reload remain open.

Historical protocol v14 / Android `.24` testing: in addition to the read-only Guest Worker
session panel, Local Play now offers best-effort host discovery and six cancelable fresh-session reconnect
attempts with backoff. Discovery detects its routed Wi-Fi address, sends both limited and directed local
broadcasts, and binds an explicit IPv4 wildcard; live socket inspection found that Android `.23` otherwise
opened discovery port `22123` as IPv6 while the working game port was IPv4. Discovery remains only an address
hint and manual entry remains available; every join still requires the compatible hello and host-owned
snapshot. Automated coverage passes 1,809 checks with no failures. The exact `.24` APK is installed on the
SM-J410G and SM-S938U. On the current router, direct discovery traffic and manual joining work but wireless
broadcast discovery is filtered; manual join, two-worker movement replication, both phone-aspect session panels,
bounded exhaustion/manual fallback, and prompt host-restart automatic reconnect all passed. Hotspot or another
broadcast-capable network plus maintenance, relocation, truck, vendor, and outstanding Windmill checks remain.

## Direct Internet multiplayer (engineering)

Accountless, no-fee Direct Play for players on separate networks is under active development but is not
yet selectable in a production build. It is designed without an operated matchmaking or relay service,
so it cannot be universal: one player's router or IPv6 connection must be reachable, and restrictive
CGNAT or double NAT cannot always be crossed without a relay. The encrypted transport and reproducible
Windows/Android native candidates are present and intentionally fail closed. Physical ARM32 and ARM64
Android devices pass the native/Lua conformance checks, a same-LAN encrypted ENet/Direct exchange, and
an encrypted bridge exchange across separate Wi-Fi and cellular routes on all three game channels. An
isolated full-game acceptance now also passes the actual two-code player flow across those routes.

Bounded PCP/NAT-PMP codecs, a serialized finite-lease coordinator, and strict UPnP IGD handling are
covered by engineering tests. Windows now also has non-production live PCP, NAT-PMP, and UPnP adapters.
Their UDP discovery and TCP control sockets are pinned to the discovered source IPv4 and interface index.
They revalidate the exact route before create, renew, and delete; accept replies only from that gateway;
own one finite mapping at a time; and never receive an invitation secret. The paired encrypted IPv4 listener binds the exact internal address
before mapping, accepts the router-selected public endpoint only after global-unicast classification, and
closes before deletion. A local no-traffic probe passed both real bindings without creating a mapping or
invitation. Windows route discovery now carries a process-local generation advanced by OS IPv4 route,
interface, and address-change notifications, and every mapping operation requires that generation to remain
unchanged. Android still needs an exact-`Network` socket bridge, release loading remains restricted to
engineering builds, and no physical router mapping has passed, so automatic mapping remains unavailable
to players. A self-contained Windows Host/Guest acceptance kit now guards the first remote residential test
with a no-traffic preflight (including the exact UPnP transport), a two-minute lease, an exact interface/profile/program/UDP-port firewall rule,
encrypted three-channel checks before and after renewal, listener-before-delete shutdown, exact deletion
acknowledgement, and redacted results. See
[`docs/public_ipv4_remote_acceptance.md`](docs/public_ipv4_remote_acceptance.md). The current residential
gateway did not answer PCP, NAT-PMP, or SSDP discovery. A guarded cellular-to-Wi-Fi
IPv4 run then classified the gateway-reported WAN address as carrier-grade NAT and stopped before any
package, listener, or router rule was created. Manual IPv4 forwarding cannot cross that upstream NAT.
Both physical phones have global IPv6 addresses and IPv6 default routes. A temporary LuaSocket UDP6
probe proved that both app runtimes can bind/use IPv6 while the host stays on Wi-Fi and the client stays
on cellular, although the first one-way-listener attempt timed out. The live BGW530 Firewall menu then
confirmed that its dormant IPv6 `PinHole` chain is not exposed; Packet Filter is not a safe substitute.
A second guarded probe bound the same UDP6 port on both phones and sent one-time-token checks in both
directions from the final sockets. That simultaneous opening passed across Wi-Fi and cellular without a
router change: both phones received the authenticated hello and acknowledgement, the separate routes
were reverified, both diagnostic packages were removed, the sensitive build tree was deleted, and no
public IPv6 address or token was retained. This proves a free two-code IPv6 path on the tested networks.
A strict IPv6 parser/classifier and fixed binary `TPS2H` host-code / `TPS2R` reply-code codec are now
joined by ABI-v3 native response authentication, a replay-safe simultaneous-opening controller, and an
authenticated fragmenting IPv6-to-loopback bridge for the existing ENet transport. The reproducible
provider has exactly 24 exports. Its no-network response/opening/bridge conformance probe passes on both
physical ARM32 and ARM64 phones with verified package removal. The guarded physical bridge probe has now
also passed: authenticated opening transferred the final sockets into encrypted ENet, game traffic moved
in both directions while exercising channels 0, 1, and 2, and both phones observed authenticated bridge
fragmentation. The routes
were reverified, the diagnostic packages and sensitive tree were removed, and the retained report holds
no public address or one-time credential. The subsequent full-game run opened the host save, applied the
protocol-v9 snapshot, reached Direct 2/4, moved the remote player, executed loading-bay and cutter actions,
cleaned up a departing guest, rejected a stale invitation, and reconnected with a fresh invitation. Its
redacted report likewise retains no address, code, or key.

The PC version is now included in this engineering gate. A Windows PC hosting over Wi-Fi and an Android
guest on cellular passed two fresh full-game Direct sessions on August 31, 2026. Both used the real host
approval panel and completed authenticated opening, snapshot/HUD synchronization, movement, loading-bay
control, and cutter safety control. One ended through the PC host's confirmed removal control and the
phone observed the kick; the other ended through a graceful phone departure. Secret scanning and cleanup
passed, and the redacted report retains no endpoint, device serial, invitation, key, packet, raw log, or
internal run identifier. The complete packaged smoke suite passes 1,715 checks with zero failures.

A guarded repeat of both PC-host/Android-cellular sessions also passed the packet-privacy gate. Capture
was limited to full IPv6 UDP packet bytes on the selected NIC and Direct port, showed authenticated bridge
traffic in both directions, and contained none of the registered invitation, player-name, or gameplay
plaintext canaries. The private capture, sole owned filter, endpoint, and temporary artifacts were removed;
only the redacted acceptance report remains at
`output/native-crypto/device-tests/pc_android_direct_packet_capture_report.json`.

The guarded Windows-PC-host plus two-Android run passed on August 31, 2026, with the PC host on Wi-Fi,
one Android guest on Wi-Fi, and one Android guest on cellular. Sequential fresh invitations and explicit
host approval brought all three devices to Direct `3/4`; the host removed the first guest, the second guest
remained active at `2/4`, and its graceful departure returned the host to `1/4`. The exact Windows
engineering allowance for UDP ports `57842` and `57844` was verified. After the run, the helper-owned
narrow rule was removed and the pre-run firewall state was restored.
Cleanup and secret-redaction checks passed. This remains engineering evidence and does not change
`productionReady = false`.

The guarded player flow is now implemented behind the production gate. `Host Direct Game` loads and
preflights the selected host save, binds the IPv6 socket before creating an expiring `TPS2H` code, and
accepts only its matching authenticated `TPS2R` reply. `Join Direct Game` returns that reply and keeps the
same socket alive until it transfers into encrypted protocol-v13 transport. The screen supports deliberate
copy/paste, clears a code it placed on the clipboard after use or cancellation, never includes a code in
status/error text, and requires each player to enter the global IPv6 address shown by their own device.
After encrypted authentication, the joining worker remains quarantined until the host approves the
in-game request; no player slot or shop snapshot is disclosed first. Hosts can also decline or remove a
worker from the keyboard/mouse/touch panel. Decline, removal, timeout, and disconnect close that
one-connection invitation, so reconnecting requires fresh codes. Valid authentication attempts are
rate-limited before native handshake allocation, while wrong invitation prefilters allocate no crypto state.
One Direct host supports up to three guests, for four players total. Each guest is admitted with a
sequential fresh invitation; an invitation is not shared across multiple joins.
Local Play still uses its original transport. The normal title screen does not expose Direct Play while
the bundled native provider remains `productionReady = false`.

For two-computer engineering tests only, Direct Play can be explicitly exposed by setting
`PICTURE_SHOP_ENABLE_DIRECT_TEST=1` before launching the game. This does not change the provider's
`productionReady` marker or enable Direct Play in packaged/release builds; it creates a clearly marked
engineering proxy only when the verified native candidate reports `engineeringReady = true`. The host
and guest still need usable global IPv6 addresses, the expiring two-code flow, host approval, and the
required narrow UDP firewall/network configuration. If the native provider is unavailable, the menu stays
locked.

Windows engineering launch example (run in the game folder):

```powershell
$env:PICTURE_SHOP_ENABLE_DIRECT_TEST = '1'
& 'C:\Program Files\LOVE\love.exe' .
```

If the native DLL is outside the paths searched by `src/net/crypto_native.lua`, set
`$env:TPS_CRYPTO_LIBRARY` to the verified `tps_crypto.dll` before launching. The host and guest must
each enter their own global IPv6 address and exchange fresh, expiring host/reply codes. A public IPv4
address alone is not sufficient for this path; IPv4 requires the separate guarded mapping/forwarding flow.

The guarded IPv4 flow remains available for a different host network with a public address. It uses a
random port and matching temporary rule name,
a hidden WAN-address prompt, an endpoint/key-bearing build tree outside the OneDrive project that is
removed after installation, process-scoped Android logs, and a 12-minute watchdog. It verifies before
and after the exchange that the host remains on Wi-Fi and the client remains on cellular with Wi-Fi
off. Completion must prove both probe packages are absent and the host socket is released, and the user
must confirm removal of the temporary router rule. The guarded encrypted IPv6 bridge runner is
`tools/run_android_ipv6_bridge_probe.ps1`; its live separate-network transport gate has passed. The
production gate remains closed pending the broader network and Android runtime matrix, packet-capture
coverage across the remaining network/runtime matrix, hardening, and external security review. See
`docs/direct_internet_multiplayer.md` for the current evidence, cleanup requirements, and honest
limitations.

## Release gate

From a clean, pushed `main` branch, run `./RELEASE.ps1`. This single command
checks Git/upstream integrity, versions, the engine regression suite, raster
assets, licensed audio sources, mobile-package provenance and contents, and the
final SHA-256 checksum. It writes `output/release/release-report.json` and fails
without producing a passing report if any gate is not satisfied. Use
`./RELEASE.ps1 -BuildApk` to additionally build and verify the signed development
APK. Before it assembles tester downloads, that path requires a completed
`output/mobile/device-tests/guest-worker-physical-acceptance.json` bound to the
exact clean-source APK and all required three-phone checks. Physical-device
installation and observation remain manual; their recorded result is enforced
by the release tooling rather than inferred from an automated build.

## Phone and controller input

- Touch: drag the lower-left control to move and use the contextual lower-right work button. Extra
  **Lower**, **Park**, **Move**, and **Turn** buttons appear only when the pallet jack or a relocating
  machine can use them. Tap an eligible skid directly to lift that exact skid.
- The shop floor fills ultrawide phone displays. Two-finger pinch-zoom and pan works on the title,
  shop floor, computer, machine consoles, manifests, quotes, vendor, and press screens. Each screen
  remembers its own view; one-finger taps and the movement/action controls keep their normal behavior.
- Touch every menu, computer, manifest, quote, and machine panel directly. Numeric/text fields open the
  Android keyboard. Android Back closes the current panel through the same safe exit route as Escape.
- Controller: left stick or D-pad moves; **A** uses the current shop interaction; **X** parks the pallet
  jack; **Y** begins machine relocation; right shoulder turns a relocating machine; **Start** saves and
  returns to the shop menu.
- Keyboard movement accelerates and brakes smoothly, slides along blocked edges, and keeps diagonal speed
  consistent. Press **E** or click the gold-marked nearby target to interact; controller prompts show **A**.
- On panels and menus, either stick moves the gold controller cursor, **A** clicks, **B/Back** closes,
  and the D-pad retains menu/help navigation. At the Polar cutter, left and right shoulder are the two
  independent guarded cut controls; **X** clamps and **Y** rotates the sheet.
- The launcher icon is generated only from the supplied front-facing Polar paper-cutter image at
  `mobile/android/polar-cutter-launcher.png`, without a character, border, or added badge.

## Title and saves

The title screen has three local save slots. Use **W/S** or the arrow keys to select a slot, **N** for a new shop, **C** or **Enter** to continue, **D** to delete, and **Q** or **Escape** to quit. Confirmation prompts accept **Y** or **Enter** and cancel with **N** or **Escape**. Starting a new shop in an occupied slot always shows an overwrite warning; cancelling it leaves the existing save unchanged. Saves are versioned and retain money, stock, finished prints, completed cuts, and player position.

Save format 14 retains active, completed, and declined jobs, accounts receivable, reputation, customer-stock claims, grouped procurement shipments,
stock, film, machine placements, pallet-jack ownership, wrapper placement, and the next stable
job number, the cutter's player-saved measurement history, the business calendar, and unpaid bill
ledger, pending, received, and answered client emails, sent promotions and player quotes, plus uniquely tracked machine condition,
component wear, cycles, maintenance history, pending machine deliveries, client artwork and stock specifications,
and physical press-pass progress. Version-1 through version-13 slots migrate
when loaded. Saves are validated in a temporary
file before promotion and retain the previous valid slot as a backup. A damaged primary recovers
automatically; a slot with no valid recovery copy is marked as damaged instead of appearing empty.

## Job rules foundation

- A cutting job accepts 1–5 customer pallets with 500–3,000 sheets on each pallet.
- The largest incoming parent sheet is 25×25 inches, and the finished size must fit the parent sheet.
- The Polar lift capacity is 500 sheets. A partial final lift is allowed and billed as a full lift.
- Each lift is quoted at $150. Five 3,000-sheet pallets therefore quote at $4,500.
- New shops begin at 0 (Unrated) with small trial work. Completed pickups build a saved -100–100 reputation that
  unlocks larger, higher-paying jobs. Established shops sometimes attract demanding premium clients who
  pay more but apply a larger reputation penalty when their stock is spoiled.
- Optional Original Heidelberg 10x15 printing work adds a separate cost budget for processed plates,
  ink, chemistry, tympan, makeready, wash-up, labor and machine overhead. The machine's 5,500-impression/hour
  maximum is retained as a specification while quotes use a conservative 3,000 sellable impressions/hour.
  Cutting-only prices remain unchanged; see `docs/heidelberg_windmill_10x15_report.md` for the sourced model.
- Job offers retain a recommended production estimate, the player's submitted quote, and separate mutable progress for every pallet.
- Every pallet now owns a stable paper-batch ID, job artwork ID, live width/height, orientation,
  four margins, four-cut program, and complete cut history. Easy jobs use matching opposing margins;
  medium and hard work uses asymmetric margins that require different backgauge positions.
- Every print order names the client's supplied artwork file, exact stock grade/weight/finish/color/grain,
  ordered copies, supplied sheets, and the allowance available for proofs and spoilage. The first offer after
  a Windmill is installed is guaranteed to be a print order; later offers mix cutting and print work.
- Each generated job carries a structured artwork record and compatible `artworkKey`; every paper batch keeps
  that identity. Every 128x128 texture in `assets/generated/artwork/` is registered and rotates through new
  print offers, proofs, plates, press sheets, pallet previews, and finished-job records.
- Requesting details at reception schedules the client's written job email without awarding the work.
  A job enters `awaiting_delivery` and records accounts receivable only after the player sends an estimate
  and the client's delayed acceptance email arrives.
- Declining a written request archives the numbered ticket and cancels its quoted pallets.

## Controls

- Move: **WASD** or arrow keys
- Interact with the office computer, wall-mounted work phone, or Polar 115: **E**
- At reception, press **E** to open the customer's cutting or print-order paperwork.
- Review the job sample and click **Request Email Details**. No price or award is decided at the counter.
  **Back** and **Escape** close the paperwork without deciding, so the customer remains available.
- At the office computer, press **E**, click the address-bar dropdown arrow, and choose Active Jobs,
  Completed Jobs, Deliveries, Estimating, Calendar, Inventory, the retro CritterNet WWW browser, Email,
  or Bills. The current section appears in the CritterNet URL field instead of a row of tabs. Deliveries includes customer inbound jobs,
  outbound pickups, and vendor purchase orders; Inventory includes every currently usable supply.
- Click a job row to inspect its cutting ticket and pallet progress; click **Back** to close the computer.
- The work phone hangs on the outside face of the office's left wall. Its lamp is cyan-green for customer
  orders, amber for supplier/service calls, red-magenta for urgent current-job questions, and dark when idle.
  Customers can place a new order or ask where an active job is and when it should be done. Supplier and
  service callers can report delivery status or arrange maintenance-supply orders; completed calls remain in
  the phone history, and phone orders continue through the shop's normal written email and receipt workflow.
- Completing, delivering, and receiving payment for a client's first job establishes a repeat-client
  relationship. That company can send a varied follow-up request by email 1-3 game days later. The
  computer's **Estimate** tab shows the sender, proposed dimensions, pallet and sheet quantities,
  packaging, stock-arrival service, and estimate expiration. Enter and send a three-day estimate or decline
  the request. Client decisions arrive later, never instantly. Unanswered requests receive one or two follow-up
  emails and then go quiet. From a completed
  job, **Email 10% Promo** opens a message composer where the player can add a personal note. A customer
  may request another job, send a thank-you and save the coupon for later, or not reply. The live response
  chance rises with every character in the personal note, up to the 240-character limit. New-job replies
  automatically show the standard price, 10% discount, and discounted quote total. Email jobs use separate
  stable IDs and the same delayed truck workflow as walk-ins. Client reply arrival times are intentionally
  hidden from the Calendar. Each completed job can send its 10% promotion
  only once. Answered messages leave the inbox immediately, and another message must be selected before replying.
- One in-game day lasts five real minutes. The viewable office calendar advances through weekdays, months,
  leap years, and years and automatically projects job stock and product and machine deliveries,
  pickups, completions, rent, and bills. On the first of each new month the
  shop receives a $1,650 operating invoice: $1,200 warehouse rent, $240 power, $85 water, and $125
  internet. Use the computer's **Bills** tab to pay the full outstanding balance; unpaid months carry forward.
- Every scene and GUI has a visible mouse-clickable **Back**, **Exit**, or **Exit to Menu** control using
  the shared Polar-style physical button sprite. The visible button and **Escape** use the same close
  behavior on every screen; customer and vendor closes leave the visitor waiting. The vendor catalog
  also has a Polar-panel `NO THANKS` button that dismisses the salesperson without buying.
- Reception visits begin after randomized opening intervals, then customers return after 60-150 seconds
  and salespeople after 120-240 seconds. A waiting, reviewing, entering, or exiting visitor pauses the
  other visitor's timer so the shared entrance and reception desk never become overcrowded.
- Reception is closed on Saturdays and Sundays. Scheduled customer and salesperson countdowns pause
  for the entire weekend and resume with their remaining time on Monday; no new visitor enters while closed.
- Accepting a job records its promised stock-arrival service instead of spawning a truck immediately.
  **Express / Urgent** deliveries arrive after 2-6 in-game hours, **Quick** deliveries arrive the next
  day, and **Standard** deliveries arrive after 2-3 days. The service and remaining estimate appear on
  the customer ticket and office computer. Only after that calendar window opens can the inbound truck
  schedule; the loading bay then opens automatically before it reverses rear-first along its isometric
  body axis into the door.
- At a parked truck's rear, press **E** to open or close its animated cargo door. The wall door cannot close while a truck occupies the bay.
- When the truck cargo door is open, press **E** to open its manifest. Click **Unload** for each
  pallet; every click animates a uniquely tracked paper pallet from the truck onto the warehouse floor.
- Customer and vendor pallets share five marked receiving lanes. Each unload reserves a clear lane;
  when all five are occupied, unloading pauses without changing the job, order, stock, or money. Use
  the pallet jack to move a staged pallet away from the dock, then return to the manifest to unload.
- Hover a warehouse pallet to see its company, job ID, sheet count, paper ID, current dimensions,
  status, and location. Pallets are saved, depth-sorted, and block walking.
- Near the yellow pallet jack, press **E** to operate it. Drive with **WASD/arrow keys**, then click or
  tap an eligible skid to lift that exact skid. Choose a green floor-grid space and press **L** (or tap
  **Lower**, or use the controller's left shoulder) to set it down precisely. Normal **E/Use**
  interactions remain available while pushing.
- Press **F** to park and release an empty pallet jack. Loaded jacks move more slowly and use a larger
  collision footprint; placement is rejected when walls, machines, trucks, or other pallets are too close.
- After the manifest is empty, click **Close Cargo Door**. The truck leaves and the bay closes automatically.
- Warehouse purchasing is handled by visiting salespeople at reception. Paper, press-supply, packaging,
  and maintenance representatives arrive in rotation and wait until the player talks to them with **E**.
- Each salesperson opens a mouse-clickable category catalog. Purchases deduct cash immediately and create
  a tracked purchase order; the goods arrive later by truck at the loading dock instead of appearing instantly.
  After a supply order, the salesperson sends an email confirming that the request is going back to the shop.
- The office computer Inventory tab is a read-only stockroom count. The **WWW** tab opens
  `www.thecritternet.com`, a 1990s-style browser with Paper Depot, Pressroom Supply, Carton & Wrap,
  WrenchWorks, and Machine Market pages. Its globe, paw-network, modem, mail, sparkle, and loading sprites
  share one animated pixel-art set. Salespeople offer larger pallet quantities at a lower per-unit bulk price.
  CritterNet supplies and machines are added to a shared cart first. The checkout screen lists quantities
  and the full total before charging cash, then sends a separate receipt email for every resulting order.
- CritterNet's **Machine Market** page sells professionally inspected machines in strong condition and shows
  every uniquely numbered shop machine, its weakest component, cycles, installation state, and condition-based
  resale value. An online purchase reserves its unique machine immediately but does not add it to the shop yet:
  a dedicated loaded flatbed truck brings it to the dock, where the player opens the manifest and clicks
  **Unload**. The flatbed visibly becomes empty and can then be released. Used-machinery salesmen offer cheaper
  units that tend to have substantially more wear.
- Cutter and skid-wrapper use degrades model-specific components and total condition. Maintenance kits are
  available from the tools supplier; the machine-service contract exposes stable interactive scene IDs so each
  machine can receive its own moving-sprite maintenance minigame without changing saved machine records.
- Vendor goods unload as distinct directional product pallets. They show product/quantity tooltips and can be
  lifted, driven, and lowered with the pallet jack while retaining their last assigned direction.
- Near an unoccupied loading bay, press **E** to open or close the roll-up door manually.
- Operate an empty pallet jack and drive it beside an unloaded cutter or skid wrapper to reveal **M: Relocate**.
  Press **M** to lift the machine, use **WASD/arrow keys** to move it slowly, **Q** to rotate it, click a
  green floor-grid space, and press **E** to lock it there. Red spaces are blocked. Relocation is unavailable
  without the pallet jack.
- Cutter: lower unfinished customer pallets into the expanded feed-side staging area beside the cutter, then open the console. The feed side follows the cutter's current orientation. **LOAD JOB** or **L** opens a nearby-pallet menu, where the operator chooses the exact pallet to load. A pallet still owned by the jack, on the wrong side, or outside the 140-pixel feed radius cannot load. Click the **TYPE** field, enter a backgauge position, and press **Enter** or click **SET**.
  **M** saves the current measurement for the selected cut number. **G / AUTO SET** recalls only player-saved measurements, newest first, and cycles through the last three values saved separately for CUT 1, CUT 2, CUT 3, or CUT 4. **P** pushes/positions;
  **Q** rotate the paper counter-clockwise into the next front-edge cutting position, **Space** clamp,
  and **J + K** together start the guarded cut. The active margin is always nearest the screen.
- Cutter repeat programming: **V** recalls the newest measurement for the selected cut, **[ / ]** changes
  the selected cut program, and **U** pulls each completed lift off the bed and returns it to its pallet.
  **Run Next Lift** reloads uncut sheets but never performs cuts automatically; every lift requires the full
  rotate, position, clamp, and four-cut sequence.
- Cutter safety interlocks still enforce the barrier, clamp, E-stop, and cut controls, but they do not
  protect the player from a wrong program, rotation, or backgauge setting. An off-size blade pass spoils
  only the active lift, removes those sheets from the original skid, records the waste, and lowers reputation.
  Bills receives the replacement-stock cost plus a full-lift redo charge. The customer then sends a separately
  tracked replacement skid containing exactly the ruined quantity through the normal truck-delivery flow.
- Cutter output searches the surrounding floor for a walkable position clear of walls, the truck,
  equipment, the pallet jack, and other pallets. If every output zone is blocked, move the obstruction,
  reopen the console, press **L** to resume the completed batch, and then press **U** again.
- Every cutter action is also mouse-clickable. The two on-screen cut controls must be clicked within
  the same 0.30-second safety window as the keyboard controls.
- Cutter safety: **B** toggles the light barrier; **X** triggers emergency stop; **R** resets
- The **Original Heidelberg 10x15 Windmill** appears in the machine website and used-machinery dealer.
  Its flatbed delivery must be unloaded before use. The installed press has four floor-facing views and
  a saved position. With the press idle and unloaded, operate an empty pallet jack beside it and press **M**
  to relocate it; **WASD** moves, **Q** rotates, and **E** locks it on the floor. A carried machine renders
  above the jack forks.
- Open the Windmill with **E**. Its Polar-panel-inspired screen is fully mouse-clickable and contains
  **Run, Plates, Setup, Proof, Service, Help,** and a sprite **Exit** button. Physical shortcuts use the same
  control functions: **M** motor, **F** feeder, **I** impression, **+/-** speed, **X** emergency stop,
  **R** reset, and **Space** start/stop production.
- Every ink color needs its own stable, job-numbered plate. Order a processed plate with a one-day lead
  time or use one plate-room kit to expose, wash, dry, and mount it through the timing minigame. Cut stock
  must be staged within the marked press-side working radius, its next plate must be mounted, and prior colors
  must be dry before loading. The load screen compares the client's ordered copies with the physically supplied sheets.
- Complete chase lockup, tympan/packing, roller stripe, ink, feeder, and register checks; then run the
  motor, feeder, and impression to pull a proof. Each proof consumes one supplied sheet and displays the
  actual client artwork. Inspect it, verify the art/file match (**V**), and approve only when registration
  reaches 82%. Once approved, production tracks actual impressions, good sheets, spoilage, run hours,
  component wear, and plate life.
- The feeder check follows a visible operator sequence: fan and load the stock, test one sheet, adjust
  suction and separating air from the specific pickup/double-feed/flutter diagnosis, and confirm three
  consecutive clean single-sheet feeds. Light, medium, and heavy stock use different feed profiles.
  High speed, poor setup, and worn rollers, grippers, suction, or ink distribution raise waste.
- A finished color pass requires press wash before unloading. Uncoated work dries for two game hours;
  gloss work dries for eight. Two-color work returns for another complete plate/setup/proof/run/wash pass.
  The office job ticket shows its press sequence, actual production totals, actual supply spend, and quoted
  supply budget; printed pallets continue
  through boxing/wrapping and truck pickup normally.
- Press supplies are sold from the office computer in smaller retail packs or by the press-supply salesman
  in discounted bulk quantities: black/color ink, press wash, tympan, and plate-room kits. Routine service
  uses maintenance kits and an ordered lockout sequence. A $350 field technician visit restores timing,
  suction, lubrication, and safety systems on the following game day and sends a service email.
- Computer and salesman supply purchases wait four game-hours before dispatch. Purchases placed within one
  game-hour share one grouped truck manifest instead of spawning separate trucks. Maintenance kits remain
  physical product pallets until used; the empty kit pallet despawns after service.
- Cutter and Windmill Help use forward/back pages with complete job, supply, setup, production, cleanup,
  safety, blade-change, and maintenance instructions. Scheduled field calls spawn a differently dressed
  mouse blade technician or lizard press technician who enters through reception, services the machine,
  and walks back out.
- Close a GUI: **Esc**

The cutter table starts clear and paper appears only after **L**. Inventory is consumed only when a safe cut finishes.

New shops begin with 20 shipping cartons and one full stretch-film roll (11 wraps), enough to run the first basic boxed and flat packaging work without an immediate supply order. A completed flat pallet uses the finished wrapped-pallet sprite in the warehouse.

Artwork rendering keeps the structured job artwork as the saved identity and resolves it through the artwork
library at draw time. The same client image is composited onto the order, plate, proof, live press sheet,
pallet, and completion views, while the reusable inspection sprites remain blank underneath. New artwork
should be added as a 128x128 transparent nearest-filtered PNG and registered in `Config.paths.artwork`.

## Validation

- Double-click `RUN_SMOKE_TEST.bat` to run the isolated domain suites, focused engine integrations,
  audit-coverage manifest, and three-frame render gate. Its report is written to
  `.stabilization/smoke-report.rpt`; the suite layout is documented in `docs/testing.md`.
- Double-click `RUN_SPRITE_MOTION_TEST.bat` for the visible sprite motion lab. It runs the same smoke
  checks, then keeps an animated raw-versus-normalized character comparison open until **Esc**.
- Run `python tools/asset_doctor.py --report output/asset-audit.json` to audit the project-bound raster assets without changing them.
- Audio credits ship in `assets/audio/SOURCES.md`. Run
  `python tools/generate_sfx.py --verify-only` to verify every licensed source
  recording against the release manifest without rewriting cues.
- Warehouse props are ready in `assets/generated/`: `empty-pallet.png`, `paper-stack.png`, `toolbox-small.png`, `toolbox-large.png`, and the three-variant `paper-storage-boxes-strip.png`.
- The active warehouse background is `assets/generated/warehouse-layout-final.png`: the approved 1536x1024 warehouse sprite with factory floor in front, loading dock upper-left, separate office upper-middle, and a client lounge in the upper-right with a couch, two armchairs, and a coffee table. Its matching walkmask is `warehouse-layout-final-walkmask.png`.
- The starter shop includes a movable skid wrapper based on the `stretchWrapper` references. Customer paperwork specifies flat or boxed pallet packaging. Move finished pallets beside the wrapper, press **E**, click the exact pallet ID in the nearby-pallet list, then press **L**, **Space**, or **WRAP PALLET**. Once its three-second cycle starts, finish the cycle before exiting, resetting, or relocating the wrapper. Each film roll wraps 11 pallets; order replacement rolls from the packaging salesperson and receive them at the loading bay. Use **M** near the wrapper to relocate it and **Q** to rotate it.
- Character sources in `assets/Characters/` are processed with the Mouse Frontier sprite doctor and installed as transparent, nearest-filtered strips in `assets/generated/characters/`. The playable rabbit now uses this same modular contract, with a clean four-pose distance-synchronized walk and two-pose idle, so later playable characters do not require a custom renderer. The loader also registers the original visitor types plus the business-dragon, business-fox, and business-cat client roster with idle, walk, and sit actions. Clients rotate through the lounge seats, remain seated while waiting, and leave after five minutes without a conversation.
- `loading-bay-door-strip.png` contains five transparent closed-to-open layers. The open state reveals the exterior parking lot while preserving the approved warehouse pixels outside the doorway.
- `delivery-truck-open.png` is the independent open-body truck sprite. `truck-cargo-door-strip.png` supplies five aligned rear-door layers from closed to fully open.
- `machine-delivery-flatbed-loaded.png` and `machine-delivery-flatbed-empty.png` are aligned machine-delivery
  truck states. Machine deliveries use these instead of the box truck and switch states when the player unloads.
- `polar-operator-console.png` supplies the new front-view machine. Separate button, clamp, and blade
  strips animate the physical controls while the touchscreen and work-order program remain interactive.
- `polar-cutter-directions-strip.png` supplies eight 45-degree shop-floor views. The cardinal intermediates
  smooth the cutter's rotation while the rear views correctly show the machine's service panels.
- `loaded-paper-pallet-directions-strip.png` contains four correctly oriented loaded pallets with the
  paper resting directly on the deck. Empty and loaded pallet-jack strips use eight movement directions
  while reusing those approved four pallet views unchanged.
- `vendor-product-pallets-atlas.png` contains four-direction pallet art for paper stock, press supplies,
  packaging supplies, and maintenance equipment.
- `heidelberg-windmill-directions-atlas-v1.png` contains the four saved floor directions for the authentic
  compact platen press. Its light generated backdrop is removed at runtime by the Windmill-only shader.

LÖVE is required for the in-engine smoke test. The asset doctor can run independently with Python and Pillow.

## Project structure

`main.lua` delegates every callback to `src/app.lua`. World simulation and rendering are separate,
screens share `src/screens/ui.lua`, and domain/integration checks live under `src/tests/`. See
`docs/asset_manifest.md`, `docs/testing.md`, `docs/coding_conventions.md`, `docs/asset_pipeline.md`,
and `docs/polar115_research.md` for the runtime boundary, test map, conventions, and production research.
