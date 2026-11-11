# Campaign opening: beat audit — November 10, 2026

This review follows the [Story outline](outline.md) in player order. The focused Story and warehouse-condition smokes use fresh isolated test saves. The Story smoke runs continuously from packing through the generated road ride, dismount, porch walk, and Grandpa's conversation. It also exercises free travel after the keys, both visit orders, both interior entries, and the first shop repairs. A full physical ride and restoration playthrough through grand opening remain future work.

| Beat | Current state | What the smoke establishes | Remaining gap |
| --- | --- | --- | --- |
| Choose Story | Playable in the local New Shop flow | Story and Quick Start can be selected; Story starts closed and Quick Start stays open | **Host New Shop** setup lobby and shared start are absent |
| Pack and leave Millhaven | Playable illustrated cutscene | Packing, street departure, skip, paused game clock and save/Continue replay render and transition correctly | Extra character motion between key poses is polish |
| Travel to the farm | Illustrated bridge and farm-road montage, then native road ride | The motorcycle follows a connected generated route on several town seeds; desktop and forced-mobile smokes render the town; route terrain loads ahead of the rider | Shared multiplayer presentation is still pending |
| Arrive and approach Grandpa | Scripted parking, dismount, gear removal and porch walk | The continuous Story smoke reaches Grandpa without moving the test character directly into interaction range; save/Continue keeps the parked bike and on-foot state | Additional walk animation and camera polish may follow visual review |
| Talk with Grandpa | Playable five-page porch conversation | Proximity gating, touch advance, keys, save/Continue, and a sibling greeting variant exist | Sibling count is read during dialogue instead of frozen at its start; the scene is not synchronized across multiplayer participants |
| Leave Grandpa's farm | Keys end the prologue and return free control at the farm, with no destination card or forced GPS route | Both map markers render; Continue preserves the free-roam handoff; both entrances work without selecting a route, in either visit order. Optional GPS selection does not lock the other door | The campaign smoke verifies connected route plans and entrances; it does not physically steer the bike across each route |
| Restore the shop | Condition/actions and visual stages implemented | The Story smoke reaches the closed shop in either visit order, reconnects power through the restoration UI, repairs the breaker, and persists the repair. A separate state smoke covers receipts, ordered cleaning, repaint, machine prerequisites, and the closed-shop job gate | The rest of the integrated restoration playthrough, machine power gates, and first-job economy still need completion |
| Hold grand opening | State transition implemented | Prerequisites prevent early opening and jobs resume afterward | Grand-opening cinematic and shared multiplayer beat are absent |

## Next implementation beat

Extend the integrated Story playthrough through floor cleaning, repainting, cutter and wrapper service, and grand opening. Verify the closed-shop economy and the first real client/job after reopening. Multiplayer lobby creation and synchronized prologue remain a separate larger beat.

The arrival acceptance smoke now checks several town seeds, a forced-mobile viewport, route movement and road clearance, streamed scene rendering, the walk, skip during native travel, Continue replay, and the five-page conversation. Interruptions replay the opening from the beginning rather than saving a mid-road checkpoint.

## Evidence

- [Story focus report](../../output/campaign-beat-audit-7618607f/story.rpt): all focused checks passed.
- [Warehouse-condition focus report](../../output/campaign-restoration-audit-67905561/condition.rpt): all focused checks passed.
- Sound Studio API tests: 8 passed, including recording and selecting a Grandpa Greeting take in isolated storage.
- Dialogue Lab smoke: 59 checks passed, including Grandpa's preview portrait and independent voice routing. No Grandpa recording was created in the project.
- [Native Story desktop smoke](../../output/story-native-handoff-fb8163cd/story.rpt) and [forced-mobile smoke](../../output/story-native-mobile-final-a23ad871/story.rpt): focused continuous opening checks passed, including generated routes from four town seeds and skip during native travel.
- [Normal commute regression](../../output/story-arrival-commute-regression-1d5d1198/commute.rpt): passed after the shared renderer change.
- [Earlier Story first-stop desktop smoke](../../output/story-first-stop-final-93cf4c1a/story.rpt) and [forced-mobile smoke](../../output/story-first-stop-mobile-8faec9f1/story.rpt): historical results before the destination card was removed.
- [Warehouse-condition regression](../../output/story-first-stop-condition-6d9c07b8/condition.rpt) and [normal commute regression](../../output/story-first-stop-commute-final-d72c50a6/commute.rpt): passed after the first-stop work.
- [Free-roam Story desktop smoke](../../output/story-free-roam-final-desktop-7ed4b098/story.rpt) and [forced-mobile smoke](../../output/story-free-roam-final-validated-3ce6d271/story.rpt): no destination card or forced GPS, both visit orders, optional GPS selection/clear/Continue, correct entrances, and first shop repairs passed.
- [Free-roam normal commute regression](../../output/story-free-roam-commute-b832df71/commute.rpt): passed.
