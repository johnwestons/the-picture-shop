# Forklift floor-cargo adapter

Current integration: normal-game world movement and warehouse commands now call this adapter. See [playable slice status](warehouse_build_status.md). The module responsibilities below remain unchanged.

`src/forklift_cargo.lua` bridges the pure forklift simulation to canonical customer/vendor pallets. It is host-only, synchronous and independent of animation. It does not enable the forklift in normal play, add wire actions, spawn purchased equipment, load/save a shop, or bypass rack/stack rules.

## Integration

```lua
local transfer = Cargo.callback(state, forkliftConfig, authenticatedPlayerId, {
    validateWorld = function(query)
        -- Derive from the current host world, never client-supplied booleans.
        -- Check usable floor, orientation/alignment, obstacles, bay permission,
        -- destination occupancy and clearance for this exact pallet/vehicle.
        return permitted, refusalCode
    end,
    -- Optional bounded ground placement correction; default is fork contact.
    dropPosition = function(forkX, forkY, detachedVehicle)
        return correctedX, correctedY
    end,
})
Forklift.attachCargo(state, forkliftConfig, authenticatedPlayerId, palletId, transfer)
Forklift.detachCargo(state, forkliftConfig, authenticatedPlayerId, palletId, transfer)

-- After authoritative Forklift.move, before publishing the resulting pose:
Cargo.sync(state, forkliftConfig)
```

The callback closes over the trusted root state/config/authenticated operator. Do not deserialize these callbacks or authorization fields from network input. The callbacks must be read-only, synchronous and non-yielding; detached query tables prevent accidental edits through arguments but cannot prevent a trusted closure from reaching other state.

## Validation and ownership

Each transfer validates the full vehicle record, paid forklift receipt/entitlement, canonical pallet/storage ownership, one-vehicle operator exclusivity, exact current vehicle view and exact pallet ID. Both directions require a stopped, attended vehicle with forks settled at ground height. No floor pickup or drop is allowed at travel/shelf height or during raising/lowering.

Customer pickup accepts only `warehouse`, `cutter_output`, or `press_output`; vendor pickup accepts only `warehouse`. Machine-owned, shelf, stacked, truck, absent and still-unloading pallets cannot be stolen. A floor pallet supporting another pallet cannot move. Rack and upper-stack handling belongs to `PalletStorage.apply`, not this floor callback.

The ground contact is derived from `Forklift.dropPosition`. Pickup/drop radial tolerance defaults to 24 world pixels; `floorPickupRadius` and `floorDropRadius` may be configured from 0 to 128. Invalid explicit tolerances are refused. Coordinates must be finite and within ±1,000,000. A custom drop resolver cannot teleport a pallet beyond the allowed contact radius. These range checks do not replace mandatory host-world clearance/alignment checks.

`validateWorld(query)` receives action, palletId, playerId, proposed x/y, forkX/forkY, detached vehicle, detached actual pallet, and its actual vendor boolean. Only an explicit `true` authorizes placement. Exceptions or other returns refuse without committing the transfer. Resolver exceptions and nonfinite results also refuse.

After all checks, one `PalletState.transition` changes both location and vehicle ownership atomically. The original pallet/paper/print identities, quantities, damage, wrapping and unrelated data survive. No duplicate cargo inventory is created. Canonical transition refusal retains the exact original world-table reference. Repeated attach/drop is rejected by the forklift domain without another callback. Request revisions/deduplication, authenticated range to the vehicle, durable persistence and reliable network publication remain the authority integration's responsibility.

## Movement synchronization

`Cargo.sync(state, config)` validates current canonical custody and writes the real carried pallet's existing `world` table from the forklift pose. It updates x/y, fromX/fromY, direction, pallet rotation and settled spawn progress while retaining unrelated world metadata and all stock data. The ground-plane anchor follows the vehicle; visible vertical offset comes from actual fork height in presentation, not world y or a second animation clock.

Sync returns `true, "synced"` only when placement changed, otherwise `false, "unchanged"` or `false, "empty"`. Malformed/mismatched state is rejected without repair, cargo loss or teleportation. A parked/disconnected raised load retains its physical location and custody; sync does not require an active operator because disconnect recovery must not discard held stock.

## Tests and gate

`src/tests/forklift_cargo_test.lua` covers real customer/vendor round trips, all eligible and ineligible floor sources, callback isolation/errors, operator/height/range/entitlement checks, malformed state, supporting-base protection, exact-reference rollback, bounded drop correction, actual movement synchronization, all eight heading rotations and disconnected suspended cargo. The suite is registered in the normal desktop/mobile smoke registry. Normal-play input, world geometry checks, cargo rendering/occlusion, network commands and purchase materialization remain gated pending integration.

Verification on 2026-09-19: all 80 cargo assertions pass in both full runs. Final desktop and forced-mobile smoke each passed 3,003 checks after the lab-framing regression additions, including startup and three rendered frames, with zero failures. Reports: `output/warehouse-build-desktop.rpt` and `output/warehouse-build-mobile.rpt`. These are local isolated smoke runs, not connected-device verification or proof that the gated forklift is available in a live shop.
