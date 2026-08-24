local Test = {}

function Test.run(context, check)
    local state = context.State.new()
    local job = context.jobs.createOffer({
        id = "DOMAIN-OWNERSHIP", company = "Domain Test Co.",
        sourceSize = { width = 20, height = 16 },
        finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
    })
    context.jobs.accept(job)
    state.jobs.active[1] = job
    local pallet = job.pallets[1]
    pallet.location = "warehouse"
    pallet.status = "raw"
    pallet.world = { x = 400, y = 400, fromX = 400, fromY = 400,
        direction = "northwest", rotation = 1, spawnProgress = 1 }

    check("domain_pallet_single_owner_transition",
        context.PalletState.transition(state, pallet, "on_pallet_jack")
        and state.palletJack.carriedPalletId == pallet.id
        and context.PalletState.validate(state))
    check("domain_pallet_rejects_jack_to_cutter_claim",
        not context.PalletState.transition(state, pallet, "at_cutter", {
            cutterRadius = context.config.cutterPlacement.palletInputZoneRadius,
        })
        and pallet.location == "on_pallet_jack"
        and state.palletJack.carriedPalletId == pallet.id
        and context.PalletState.validate(state))
end

return Test
