# Motorcycle multiplayer performance

The host simulates the bike and resolves collisions. Guests send controls at 20 Hz and receive player positions at up to 12 Hz. During a commute the host also marks the shop state dirty about ten times a second. The durable network channel coalesces these changes and sends up to four reliable updates per second, per guest.

## Bandwidth

An island contains thousands of height samples, road vertices and building records. Previously every durable update encoded the frozen island again. Protocol 65 sends the full layout on join and establishes it on the reliable update stream. Subsequent updates reference its ID. A change of island sends the full layout again. Hosts and guests need the same protocol version.

In the desktop LÖVE multiplayer harness, seed 712345 produced 62 sampled commute updates that referenced a cached town. Encoding those same states with their full towns required 9,935,131 bytes. The reference packets used 718,955 bytes, a 92.8% reduction. At four updates per second, the sample averages imply about 5.13 Mbps before and 0.37 Mbps after **per guest for this channel alone**. These figures exclude joins, realtime packets, protocol overhead and retransmissions. Host upload grows with the number of guests.

## Response and verification

Changed commute controls can send after 25 ms instead of waiting for the 50 ms heartbeat. Guest presentation estimates velocity from successive host positions and projects motion up to 120 ms during gaps. Stops and scene changes clear that estimate. The host still decides the result of each control, so initial acceleration, braking and collisions can still reflect round-trip latency.

All 21 existing commute session checks passed in the headless desktop harness while dropping every ninth unreliable host-to-client packet and delaying every seventh remaining eligible packet by one 100 ms simulation step (using packet sequence multiples of seven). Coverage included guest driving, authoritative actions, initial joins and reconnects. This measured application traffic and exercised game state. Display FPS, frame-time percentiles and physical input-to-screen latency were not measured. The host ADB service listed no phone.

There is no measured minimum internet speed for the game from this test. Compare host upload and guest download against total session traffic under load. If spare bandwidth is available, increasing the connection speed alone may do little for a guest whose delay comes from round-trip time, packet loss or slow terrain frames.

## Three-player phone sample, November 4, 2026

The PC hosted while two Android clients were connected. The USB-connected Samsung SM-S938U was on build 90. In the sampled town scene, the local player was on foot beside the motorcycle, so these measurements describe multiplayer presentation and town rendering rather than a sustained mounted ride.

Over 33.4 seconds, SurfaceFlinger recorded 55.6 FPS on average, a 16.6 ms median frame interval, an 83.2 ms 99th-percentile interval and a 124.8 ms worst interval. Thirty-one intervals exceeded 50 ms. The game's SDL thread used about 96% of one CPU core. This points to client-side rendering work as a major source of the visible stutter. The host used about 29% of one CPU core with an 800 MB working set during the sample.

The phone reported a strong Wi-Fi link at -41 dBm and 1080 Mbps. Fifteen pings to its access point averaged 9.7 ms with no loss, but individual replies ranged from 2.2 to 27.3 ms. The PC did not answer ICMP, and no in-game RTT reading was captured. The measurements therefore do not establish the phone-to-host game latency or show a need for faster internet service. Battery temperature was 40.6°C and the skin sensor read 42°C while the battery was at 8% and USB powered.

Android build 92 reduces the mobile foliage view radius from 96 m to 72 m while keeping terrain, roads and structures at the existing view radius. That trims the nominal foliage sampling area by about 44%. It also refreshes the visible plant list when the camera moves 1.5 m, turns 4 degrees in first person, the season changes, or 0.2 seconds pass. This reduces repeated plant filtering and sprite preparation when the camera is still. The package smoke run passed 10,287 checks, including a regression case for the rider gait state that crashed after a disconnect. A matching phone frame-rate sample during a mounted three-player ride is still needed to measure the gain.

## Build 92 connected warehouse sample, November 4, 2026

The updated Samsung joined the PC host. The phone HUD showed `LAN GUEST · 2/4 WORKERS` in the warehouse at the start of a 35.3-second SurfaceFlinger capture. It recorded 3,422 presented frames (96.9 FPS average), an 8.3 ms median interval, 16.65 ms at the 95th, 99th and worst intervals, and no intervals over 50 ms. The phone battery read 31.8°C before and after, with Android thermal status 0. The host used 7.2% of one CPU core and about 301 MB of working memory over the window.

This was an indoor, mostly stationary, two-worker sample. The phone showed the manual host-address dialog after capture, so the session was not confirmed to have remained connected for the entire window. These results do not compare directly with the earlier three-player outdoor sample and do not measure input-to-response delay, mounted riding, foliage performance or game-level network round-trip time. The earlier outdoor capture remains the only measured evidence for the foliage-heavy scene; its high tail latency and near-saturated SDL thread are still the main reasons for the build 92 rendering changes. Keep the 20 Hz guest input and 12 Hz host snapshot rates unchanged until a same-scene ride and game-level RTT sample show a network bottleneck.

## Box and kei truck motion, November 10, 2026

Protocol 72 adds a truck motion record to the existing 12 Hz player snapshots. Truck positions already used the common player smoothing, but the motorcycle-only fast vehicle record excluded trucks. Truck heading and speed were reconstructed from player motion, while steering, road height, pitch and dashboard telemetry depended on the durable state channel, capped at four updates per second.

Both truck models now send heading, speed, steering, brake, throttle, reverse, height and pitch with the driver's realtime position. Clients smooth the continuous fields every frame, interpolate heading along the shortest arc, and use that pose for the visible truck and dashboard. Trip/model changes, exits, scene changes and stale packets clear or reset the transient pose. Host physics, ownership and cargo authority are unchanged. All devices must use protocol 72.

The four-player session regression exercises local drivers and remote observers at 30 and 60 FPS, dropping every seventeenth motion transmission and delaying every thirteenth remaining eligible transmission by 100 ms. It covers reversing, stops, heading wrap, vehicle changes, expiry and concurrent motorcycle motion. The full-precision truck packet fixture is 916 bytes, below the existing 1,200-byte cap. Commute, protocol/session/impairment and truck-rendering smoke runs passed, including a live dashboard draw using realtime telemetry. These are desktop harness checks; the gain on physical phone/PC multiplayer rides has not yet been measured.
