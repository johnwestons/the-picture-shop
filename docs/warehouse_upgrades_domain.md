# Warehouse upgrades domain handoff

Current integration: the normal game now connects this domain to office purchases, the construction phone service, a durable raccoon visitor, four visible stages and the left storage bay. The following describes the domain module's responsibilities, not the current feature gate. See [playable slice status](warehouse_build_status.md).

This slice implements durable rules and a domain test suite only. It does not install room art, change collision/rendering, animate or dispatch an NPC, call the phone, add a forklift vehicle, save files, alter a screen, or register network commands. The integrating host/local simulation owns those effects.

## API

`require("src.warehouse_upgrades")` has no LÖVE dependency. It uses the real `state.money` cash field and `BusinessCalendar.absoluteHours(state)` when an explicit time is omitted. Mutations must only be called by the authoritative local shop or multiplayer host. These functions are not a network trust boundary: callers must validate host authority, player access, and command shape first.

- `defaultState()` returns independent locked `warehouse` defaults, not a whole shop.
- `validate(warehouse)` returns `true` or `false, reason`. It checks exact bounded shapes, deadlines, one-worker ownership, bay/project consistency, receipt consistency, and forklift entitlement.
- `normalize(warehouse)` returns a detached validated copy. Only `nil` becomes defaults. Malformed paid state returns `nil, reason`; it is never silently reset.
- `ensure(state)` fills missing legacy `state.warehouse`; returns the validated live warehouse or `nil, reason`. It does not alter unrelated shop data.
- `catalog(optionId)` returns a detached entry, or the four-entry catalog if omitted. IDs: `floor`, `storage`, `breakroom`, `forklift`. Prices: 2500, 4500, 3500, 6500. These are initial development prices, not established economy balance. `storage` includes the ten-slot warning and upper-row forklift requirement.
- `stageInfo(number)` returns name/tool metadata: 1 `concrete_float`, 2 `framing_hammer`, 3 `assembly_drill`, 4 `finishing_roller`.
- `purchase(state, bayId, optionId, requestId, nowHours)` returns `ok, projectOrMessage, code`.
- `purchaseForklift(state, requestId, nowHours)` returns `ok, receiptOrMessage, code`. Sets `state.warehouse.forkliftOwned`; does **not** create or mutate `state.forklift`. Vehicle integration must read that entitlement and spawn at a validated layout anchor.
- `activeProject(state)` returns a detached project copy, or nil.
- `pendingNotice(state)` returns `{kind="construction_notice", projectId, bayId, optionId, constructionHours=96}` while the active project awaits its arrival call. No fabricated dialogue is supplied.
- `isBayAccessible(state, bayId)` is true only after all four full work stages finish.
- `update(state, nowHours, options)` returns `changed, events` on a valid update; invalid input/state returns `false, errorMessage`. No changes means `false, {}`. Save/broadcast only after a changed update, not every simulation frame.

Successful purchase receipts use request IDs of 1–64 letters/digits/underscore/dot/hyphen. Replaying the same ID and same choice returns success with `code="replayed"` without charging. The same ID with another choice returns `request_conflict`. A new request against an already purchased bay/forklift fails without charging. Failed attempts are not receipts and can be retried after funds become available. Host save/authority must commit the money and warehouse together before acknowledging success. Never include a client price in this API.

## Persistent shape

```lua
warehouse = {
  layoutVersion = 2, nextProjectId = 1,
  bays = { front_left = {status="locked"}, front_right = {status="locked"} },
  projects = {}, receipts = {}, forkliftOwned = false,
  activeProjectId = nil,
}
```

At most two permanent projects and three purchase receipts exist: one per bay and one forklift. Projects are ordered `WUP-0001`, `WUP-0002`. No replacement, demolition, refund or second-forklift workflow is implemented. A purchased bay stores `{status, optionId, projectId}`; status progresses `reserved` → `building` → `complete`. Unpurchased bays remain `locked`.

Project fields are `id`, `requestId`, `bayId`, `optionId`, `pricePaid`, `purchasedAtHours`, `phase`, `stage`, followed as reached by `noticeCallId`, `noticeDeliveredAtHours`, `arrivalDueAtHours`, `workerArrivedAtHours`, `stageStartedAtHours`, `stageDueAtHours`, `pausedAtHours`, `completedAtHours`, `workerReleasedAtHours`. Phase progresses `queued` → `awaiting_notice` → `awaiting_arrival` → `building` → `complete`. Stage is 0 before actual work, then 1–4; four is still locked until that stage's deadline.

## Host lifecycle integration

Call `update` from the host-only simulation, including appropriate simulation screens, not from guest rendering. A first update activates the oldest queued project and emits `notice_requested`. `pendingNotice()` remains durable until confirmed, including while a customer call occupies the phone. Do not replace a live call. Integrate a real `construction_notice` phone kind and save it, then confirm actual notification delivery with:

```lua
Upgrades.update(state, now, {
  noticeDeliveredProjectId = project.id,
  noticeCallId = currentConstructionCall.id,
})
```

This starts a two-game-hour lead, not construction. The call may count as delivered when actually presented to the player or retained as an appropriate missed-call notice; the phone adapter decides that policy. Calling `update` with no delivery gate never starts an unannounced project. Notice ID and project ID must be provided together. Gate IDs must come from current host state, not guest claims.

At/after `arrivalDueAtHours`, dispatch the physical raccoon through the front entrance. When the worker actually reaches the work anchor, pass `{workerArrivedProjectId=project.id}`. Early arrival gates do nothing until the lead elapses. Missing physical arrival never auto-starts construction. The domain does not pretend the worker has traversed the room.

Actual arrival starts stage 1 with a 24-hour deadline. Each subsequent stage takes another 24 game hours. Large updates cross boundaries in order; the completion timestamp remains the true fourth deadline, not the late update time. Updates have no wall-clock/offline progression and do not debit again. On work obstruction, pass `{blockedProjectId=id}`; while paused, updates do not advance. When genuinely clear, `{unblockedProjectId=id}` shifts deadlines by the pause duration, retaining completed effort. Do not pass both block and unblock gates together. A newly detected block applies at the supplied current time after any already-crossed boundaries; call promptly when blockage begins.

Completion emits `construction_complete` exactly once and unlocks the bay. The active worker remains assigned while exiting. Only `{workerReleasedProjectId=id}` after physical exit releases the worker and allows the next queued project to request its own notice. Old project IDs cannot advance the next project.

Events contain `kind`, `projectId`, `bayId`, `optionId`, `stage`. Kinds: `notice_requested`, `arrival_announced`, `work_started`, `stage_changed`, `work_blocked`, `work_resumed`, `construction_complete`, `worker_released`. Gate replay and unchanged updates do not repeat effects. Drive the sprite's tool choice from `stageInfo`, not event count.

## Remaining integration checklist

1. Add `warehouse` to schema defaults/normalization/validation/migration and shared fields; migrate legacy absence to locked defaults without debiting money. Reject malformed paid state instead of erasing purchases. Keep receipt IDs across saves/reconnect.
2. Add host catalog GUI actions with durable request IDs, cash confirmation and the shelf forklift warning. Map only accepted host intents into purchase calls; save once and mark the shop dirty on new success, not `replayed` success.
3. Add phone queue/validation/presentation, constructor visit/path/animation runtime and host update gates. Announced appointments may appear on the calendar, but hidden customer emails must remain hidden.
4. Add collision/visual bay integration using `isBayAccessible`, not merely the existence of a purchase or stage-4 art.
5. Integrate forklift entitlement with its separate vehicle ownership/save system; raising/lowering animation is not implemented by this module.
6. Register `src.tests.warehouse_upgrades_test` in the existing domain suites, then run desktop/mobile smoke tests. This suite uses `State.new()`, the actual money/calendar shape and real busy phone fixtures, without touching player save files.
