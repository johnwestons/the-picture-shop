# Android Direct remote test — version 55

Use two Android phones on **separate Wi-Fi networks**, as requested. One phone
can be remote; neither needs to remain connected to the development PC. Both
players install the exact same `Picture Shop Direct Test` APK, version
`0.1.0-direct-test.55`, using gameplay protocol 40.

APK: `output/android-manual-direct-2026-10-18-ready/ThePictureShop-DirectTest-0.1.0-direct-test.55.apk`
(440,908,060 bytes, about 441 MB).
SHA-256: `76a0fc3214d6ab465babb251deca8c95759b5df829f989d15186d79841c260ef`.

The game package passes 6,073 desktop LÖVE checks with mobile mode enabled.
APK signature, embedded game hash, three native ABIs and 16 KB compatibility
checks pass. Installation on the phones and the remote connection are pending.

This is a private engineering build of the current game, with a separate app ID
(`com.thepictureshop.direct_test`) and save identity. Direct Play is enabled only
inside this test app. The normal game's release gates remain closed. Existing
normal-game saves are not imported. Relevant test saves may be reset if needed,
as authorized by the user.

## First connection

1. Transfer the APK to both phones and install it. If Android asks, allow the
   chosen file-transfer/browser app to install this APK. Open **Picture Shop
   Direct Test** and confirm the displayed version is `0.1.0-direct-test.55`.
2. Keep both phones on their chosen Wi-Fi networks throughout the attempt. On
   the host, select a test save slot and tap **DIRECT PLAY**, then **HOST IPv6
   GAME**. The app should select its own IPv6 address automatically. Tap
   **CREATE HOST CODE**.
3. Host: tap **COPY CODE**, send it privately to the other player, then return
   to the game promptly. Guest: open **DIRECT PLAY** → **JOIN DIRECT GAME**,
   copy the received host code, return to the game, and tap **PASTE CODE**.
   The guest's own IPv6 address should be selected automatically.
4. Guest: tap **START CONNECTION**, then **COPY CODE**. Send this reply to the
   host and return to the game. Host: copy the reply, return, tap **PASTE CODE**,
   then **CONNECT**. Each visit to a messaging app must be under two minutes;
   a longer background period cancels setup. Keep both games in the foreground
   once the codes are exchanged.
5. Host: approve the guest's join request when it appears. Confirm both phones
   enter the same shop. Move each player and check the other phone sees it;
   perform one shared interaction. Disconnect cleanly, then repeat with a new
   host code to verify reconnecting.

The host code starts with `TPS2H`; the guest's reply starts with `TPS2R`. Codes
are private and expire. Share them only with the other player, not in audit
logs or this chat. A screenshot containing a code or address should be cropped
before reporting an error.

## If it stops

Record the **first missing step**, exact error text, phone models/Android
versions, and whether the host displayed an approval request. No full invite or
IP address is needed.

- **No usable/public IPv6 address or route:** this Wi-Fi network cannot use the
  first test path. This APK does not enable Android IPv4 hosting. Try mobile
  data on the affected phone in a new attempt; cancel and reopen setup after
  changing networks so the address and invitation are fresh.
- **Host code and guest reply exist, but opening/authentication fails:** both
  local address checks passed, but remote reachability is still unproven.
  Record the exact message and keep the same network setup for diagnosis.
- **Approval appears, but no shop loads:** record the host and guest messages;
  this narrows the failure to approval, protocol or world synchronization.
- **App cannot start:** report the short visible startup status. Do not reuse
  an older engineering APK as a substitute.

Passing local automated checks or creating an invitation does not establish a
successful remote connection. Acceptance requires the real two-phone shop,
movement, interaction, disconnect and fresh-invitation reconnect above.
