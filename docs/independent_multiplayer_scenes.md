# Independent multiplayer locations — November 5, 2026

Normal town travel now belongs to the individual player. At the warehouse or
apartment exit, **Explore Town** leaves immediately without moving other players.
Guests can also plan and drive deliveries. Parking and entering a warehouse or
apartment door affects only that traveler. The grocery interior has its own
replicated scene, host-authoritative walking, and visible same-scene players.

The hosted game still owns one shop, calendar, household, town and delivery
truck. Warehouse rooms retain their existing independent scene handling. Shop
production continues while players are outside; one player's sleep cannot
accelerate time for players who are awake elsewhere.

## Implementation

- `commute/free_travel.lua` manages individual departure/arrival. Outdoor records
  are keyed by persistent resident identity, with individual origins and
  destinations. Interior locations survive saves and reconnects. Reusing a
  network slot does not adopt the previous occupant's journey.
- `commute/runtime.lua` distinguishes a shared outdoor simulation from the local
  outdoor view. Only connected travelers receive physics updates. An indoor host
  continues to simulate remote riders without creating terrain graphics, a
  cockpit or a camera. Returning indoors releases those local graphics while
  preserving shared collision data. The delivery planner reuses that world.
- Remote indoor movement no longer stops merely because somebody is outside.
  Departure releases only that player's workshop control. It preserves the
  host's menu, other players' activities and room games.
- Grocery presence, input, collision, return to the exterior, scene rendering,
  pointer routing and saves use the same authoritative session. The parked bike
  stays outside; grocery avatars are excluded from the exterior pedestrian draw.
- Delivery manifests and truck ownership remain shared. Only the assigned driver
  can load/complete that route. Other travelers retain their own destinations and
  controls during delivery stops and the off-map delivery interval.
- Home routines and bike cargo remain usable while other residents are traveling.
  Shop audio follows the listener's scene, rather than a household-wide travel flag.
- Moving travelers request durable updates at most four times per second; idle
  travel records no longer continuously dirty the entire shop. Final stops still
  trigger a durable update. Realtime player snapshots and input keep their existing
  rates. The shared calendar continues during deliveries.

Protocol **67** is required on every participant. These are source changes;
existing installed binaries do not acquire them automatically. Legacy household
trips and the explicitly disabled-town compatibility mode remain supported.

## Verification

| Suite | Passing checks, including render check |
| --- | ---: |
| Independent scenes, desktop | 55 |
| Independent scenes, forced-mobile desktop | 55 |
| Existing commute, session, protocol and save regressions | 1,253 |
| Apartment/resident/weekend/protocol/save regressions | 1,467 |
| Unattended warehouse simulation | 43 |

The new tests run the real Session/Protocol codec with one host and three guests,
plus the real application update/render/save paths. They cover simultaneous
warehouse/apartment/room/grocery occupancy, individual travel and arrival,
duplicate departure requests, guest truck delivery from loading through return,
truck exclusivity, invalid door requests, reconnects, slot reuse, household
activities, sleep, camera/input routing, audio and actual disk saves.

An indoor-host harness sample after slot reuse sent 633,138 application bytes to
three guests over ten simulated seconds (about 0.51 Mbps aggregate). Its 100
session/update steps had a 1.141 ms median and 1.446 ms p95 in the final
forced-mobile run. This idle/mixed-location sample is **not** an outdoor driving
bandwidth bound, display FPS measurement, or physical network latency test.
The renderer allocation checks establish that a remote outdoor player does not
cause an indoor host to create outdoor GPU assets.

Reports: `output/independent-scenes-{smoke,mobile,regression,home,background}.rpt`.
The grocery scene was rendered and inspected in
`output/independent-scenes-grocery.png`. Disposable primary game saves were reset
using the existing reset tool; backups were left intact.

A fresh physical PC/phone session and device frame-time measurements have not
been performed for this change. Forced-mobile testing runs on the desktop.
