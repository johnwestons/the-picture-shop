# Employee seating and pallet transport

Salespeople use the same four reception seats as clients. The visitor controller
walks to the standing approach point before switching to the existing seated
pose. Employees use new east/west chair poses with settle, relaxed, blink and
stand-up frames. Machine action selection covers production and training, and
workers face the machine after reaching its operator point.

`employee_pallet_jack.lua` is the host-owned transport controller. It approaches
the parked jack, mounts it under `operatorEmployeeId`, finds a reachable pickup,
lifts only the assigned pallet, drives to a clear machine staging point, lowers
it, and releases the jack. Pallets retain canonical `on_pallet_jack` ownership.
The empty/loaded route masks cover the full jack footprint and dynamic obstacles.
Pickup points must also fit the loaded footprint. Cached routes replan when
obstructed; blocked pickup/drop points are searched again. Alternate approach
points let a worker reach a jack parked beside another skid or machine.

The scheduler skips transfer jobs while a different employee or player operates
the jack. Ready jobs already staged at their machines can proceed. If no eligible
job can proceed, the worker asks “May I use the jack?” in their speech bubble.
Shift changes and stop requests lower the load onto clear nearby floor when
possible. If all nearby space is blocked, the jack parks with the pallet still
on its forks so a later operator can resume.

Pushing uses five authored views and mirrored westward views, with eight frames
per stride. Frames follow achieved jack travel at 10 pixels per phase; stopped
workers hold the planted second frame. Hand anchors attach each sprite to the
rendered handle. Rest poses preserve the standing body scale rather than scaling
a seated silhouette to standing height.

Source atlases were generated with the built-in ImageGen tool. Immutable base
and corrected south-facing source sheets, hashes and prompts live in
`assets/source/employee-motion-v2/`. Rebuild with:

```powershell
python tools/build_employee_motion_v2.py
```

The builder normalizes all views at one scale, corrects the authored row bounds,
mirrors the ferret's southeast source, computes anchors/bounds, and writes
versioned runtime assets to `assets/generated/employee-motion-v2/`. Review
contact sheets, GIFs, staging specs, sprite audit reports and actual game renders
are in `output/employee-motion-v2/`. The audit reports distinguish legacy action
warnings from the new strips; torso/ground anchors and game renders are reviewed
before accepting the pack.

Run smoke checks with `PICTURE_SHOP_SMOKE=1` and
`PICTURE_SHOP_SMOKE_FOCUS=employee-transport`, `employee-animation`, or
`employee-network`. The transport suite covers real floor navigation to all three
machine types, ownership, alternate jobs, requests, guest poses, save parking,
and blocked emergency drops. Workflow tests use a fast open-floor transport
fixture; collision coverage uses the actual world context.

Protocol version 30 adds employee jack ownership and larger pose rosters. Up to
ten employees and one applicant fit a dedicated `employee_snapshot` packet under
the existing 1,200-byte limit. Small rosters retain the environment packet path;
both paths share NPC tick ordering so stale packets cannot restore older poses.

Protocol version 31 replicates each player's active machine or task animation so
other players continue to see an operating pose while that player uses a GUI.
Version 32 adds dedicated computer-typing and phone-call animations to the same
direction-aware task-action replication.
