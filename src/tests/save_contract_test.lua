local Test = {}

function Test.run(context, check)
    local slot = 2
    context.save.delete(slot)
    local fresh = context.save.newGame(slot)
    check("domain_save_exact_defaults", fresh.slot == slot
        and fresh.version == context.save.VERSION
        and fresh.state.inventory.plasticWrapRolls == 1
        and fresh.state.inventory.plasticWrapUses == 11
        and fresh.state.wrapper.direction == context.config.wrapperPlacement.defaultDirection)

    fresh.state.money = 432
    fresh.state.wrapper.x = fresh.state.wrapper.x + 17
    check("domain_save_round_trip_write", context.save.save(slot, fresh.state, fresh.player))
    local loaded = context.save.load(slot)
    check("domain_save_round_trip_read", loaded
        and loaded.state.money == 432
        and loaded.state.wrapper.x == fresh.state.wrapper.x)

    local invalid = context.State.new()
    invalid.jobs.active = { { id = "BROKEN", pallets = "not-a-list" } }
    check("domain_save_rejects_invalid_nested_state", not context.save.save(slot, invalid, fresh.player)
        and context.save.load(slot).state.money == 432)
    context.save.delete(slot)
end

return Test
