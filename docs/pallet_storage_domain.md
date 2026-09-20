# Pallet storage integration contract

Current integration: left-bay racks and two-high floor stacks now have normal-game world access, shared keyboard/touch controls, rendering and host-authoritative commands. Floor stacking supports matching-footprint customer paper skids with full-height stationary forklift access. See [playable slice status](warehouse_build_status.md).

`src/pallet_storage.lua` implements host-only rack and two-high stack transfers on
the existing `jobs.active[].pallets[]` and `procurement.orders[].pallets[]`. It does
not create another pallet inventory. This domain module does not itself render a
rack, authorize network packets, persist a save, or calculate approach geometry.

## Durable data and schema

`Storage.defaultState()` returns `{revision=0,racks={},appliedRequests={}}`.
Register a completed storage bay using
`storage.racks[bayId .. "-rack"] = Storage.rackDefinition(bayId)`.
The rack is `{id="front_left-rack",bayId="front_left",revision=0}`. Rack registry
entries contain no slots or cargo. `Storage.slots(state,rackId)` derives a 2-by-5
table of stable pallet IDs; row 1 is the ground row. Empty positions are `nil`.

A stored pallet owns `location="rack"` and
`storage={rackId="front_left-rack",row=2,column=4}`. A floor-stack upper pallet
owns `location="stacked"` and `storage={supportPalletId="JOB-P02",level=2}`.
Vehicle pallets own `location="on_pallet_jack"` / `"on_forklift"` and the matching
vehicle owns the same `carriedPalletId`. The pallet itself is never copied.

`Storage.normalize(savedStorage)` returns a deep copy of valid state, or `nil,
reason` for malformed state; absent legacy state gets empty defaults.
`Storage.normalizePlacement(pallet)` validates/copies only the pallet's storage
metadata (non-storage pallets return `nil` without an error).
`Storage.validate(state)` returns `boolean, errorsArray` for registry, stable-ID,
slot, stack and both vehicle ownership invariants. Invalid ownership is rejected,
not repaired by discarding or teleporting stock. The save loader must preserve
the new locations and metadata and run full validation before installing state.

## Transfer boundary

Call `Storage.apply(state, request, validatedContext)` only on the authoritative
host. Equivalent convenience functions are `store`, `retrieve`, `stack`, and
`unstack`; those wrappers add their action when omitted.

Rack request:

```lua
{
  requestId="worker1-rack-00042", expectedRevision=state.storage.revision,
  action="store", vehicle="forklift", palletId="JOB-P01",
  rackId="front_left-rack", row=2, column=4,
}
```

Stack request replaces `rackId,row,column` with `supportPalletId="JOB-P02"`
and uses `vehicle="forklift"`, `action="stack"` or `"unstack"`.

The host constructs context from fresh world checks:

```lua
{
  playerId=1,
  near=true,       -- vehicle approach point within transfer radius
  aligned=true,    -- vehicle direction aligned with shelf / support pallet
  clear=true,      -- approach and transfer clearance checked against obstacles
  stackable=true,  -- stacking only: both load types allowed by host catalog
  compatible=true,-- stacking only: matching supported load footprints
}
```

Never accept these booleans from a client. Missing access booleans deny the
transfer. The domain also verifies the actual operating vehicle's owner, physical
position, stationary state and exact cargo ID. One worker cannot operate both
vehicles. Upper slots and stacking require a purchased forklift, with forks at
upper level (`forkHeight=1`); lower forklift transfers require ground
(`forkHeight=0`), within a 0.001 tolerance. A nonmatching target height also blocks
transfer. In-progress lifting blocks
all transfer until the fork height settles. A jack cannot access upper slots.

Success returns `true, action, receipt`; identical replay returns
`true, "replayed", originalReceipt` without changing anything. Reused request IDs
with changed contents return `false, "request_conflict"`. Other failures return
`false, reasonCode` without mutating state. Every success increments the global
storage revision; rack transfers also increment that rack's revision. The bounded
128-receipt ledger supports retries across saves/reconnects; older original
requests remain rejected by their stale expected revision even after eviction.

Only placement, vehicle cargo and revision/receipt fields change. Counts, paper
geometry, spoiled stock, job identity, wrapping, packaging, colors and drying
deadlines retain both values and existing object identity.

## Required call-site integration

- Add new locations to `PalletState` and save/network schema. Do not route rack
  transfers through generic `transitionDetached`, which lacks physical checks.
- Before **any** floor pickup (including the existing jack), machine feed, truck
  shipment or floor relocation, deny `Storage.isSupporting(state,palletId)`.
  Otherwise an older pickup path could lift a base out from under its upper load.
- Forklift floor pickup/drop remains the vehicle module's responsibility; it must
  maintain the same canonical ownership and clear storage metadata.
- Run `Storage.validate` together with existing pallet invariants after migration
  and staged transactions. Persist one durable snapshot after each successful
  transfer; broadcast durable ownership before relying on realtime vehicle pose.
- Register racks only after the bay is complete. `status="complete"` and
  `optionId="storage"` are independently checked at transfer and validation time.
- UI and both renderers must derive occupancy from `slots`; never reconstruct
  pallets from a shelf image. Rack pallets have no loose-floor world position;
  upper stacked pallets retain their base's floor anchor for elevated drawing.
- Reject remote parameters outside the strict request fields and calculate fresh
  geometry on the host. Do not reuse a guest's stale hovered target as clearance.
- Register `src.tests.pallet_storage_test` in the domain suite. The test follows
  `run(context,check)`, creates real job and vendor pallets, and builds its rack
  entitlement through the actual purchase/construction module.

## Shared physical rack screen

`src/screens/pallet_rack_screen.lua` is an instance-based, read-only presenter:

```lua
local rackScreen = require("src.screens.pallet_rack_screen").new("front_left-rack", {
    width=960, height=678,
    context=function(state,rackId,row,column)
        -- Fresh host geometry for local play; authoritative presentation data
        -- for guests. The host still recalculates these checks on submission.
        return {playerId=playerId,vehicle="pallet_jack",near=true,aligned=true,clear=true}
    end,
    onIntent=function(request)
        -- Local: return Storage.apply(state,request,freshHostContext).
        -- Guest: enqueue request to host and return nil (pending).
    end,
})
rackScreen:draw(state,fonts,assets)
rackScreen:mousepressed(state,logicalX,logicalY,button)
rackScreen:keypressed(state,key,isRepeat)
```

The screen never writes canonical shop state. Pointer coordinates must already
be transformed into the same logical UI coordinates as drawing. Touch uses
`:touchpressed(state,x,y)`. Resize with `:resize(width,height)` when logical UI
bounds change. Select by `:select(row,column)`; `:getSelected()` returns a copy.
`:view(state)` supplies stable IDs, source-variant numbers, physical action gates,
and messages without touching graphics or stock. Row 2 is the visual upper row.

Synchronous callback `true`/`false,reason` resolves the operation immediately;
`nil` means the host reply is pending. Deliver an asynchronous reply through
`:resolve(requestId,okay,message)`. Pending controls block accidental duplicate
submission. Closing a screen only closes the view; it cannot cancel a transfer
already sent to the host or destroy cargo. `:close()` and Escape return a
`{action="close"}` event. `:mousemoved(x,y)` adds hover feedback. Arrow keys
select shelves; Enter/Space chooses store/retrieve, S stores and R retrieves.

Art is lazily loaded from the approved rack and frontal-pallet source PNGs. The
background is viewed through a source quad, preserving actual geometry and
avoiding a generic inventory grid; only selected/hovered openings are outlined.
Ten opening anchors are registered to the rack's 1536-by-1024 source. The unused
foreground floor is omitted by the view quad, without editing the source image.
Three 724-by-724 pallet source cells use a shared baseline at y=648 and one scale,
so the shorter cut stack is not stretched to raw-stock height. Wrapped stock
always takes the wrapped appearance; cut/finished stock uses the cut-stack view.
Dedicated boxed/vendor/partially-wrapped frontal images are still absent from
the source pack: vendor cargo currently uses the cut-stack silhouette, with its
true product/quantity text. Do not call that placeholder exact vendor artwork.

Pass optional `fonts.title`, `fonts.body`, and `fonts.small`; otherwise the
existing game font is retained. Drawing saves/restores graphics state. A missing
or incorrectly-sized image produces an explicit art warning, not a crash or
invented replacement rack. `Screen.clearImageCache()` supports graphics reloads
and retry after fixing missing art. Register `src.tests.pallet_rack_screen_test`
in the main suite. Its presenter/input and mocked rendering checks do not
substitute for a real in-game screenshot and mobile/device visual review.
