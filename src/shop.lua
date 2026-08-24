local Shop = {}

function Shop.buyPaper(state)
    if state.money < 25 then
        state.message = "Not enough money."
        return false
    end
    state.money = state.money - 25
    state.inventory.paper = state.inventory.paper + 25
    state.message = "Bought 25 sheets of paper."
    return true
end

function Shop.sellPrint(state)
    if state.inventory.prints < 1 then
        state.message = "No finished prints to sell."
        return false
    end
    state.inventory.prints = state.inventory.prints - 1
    state.money = state.money + 12
    state.message = "Sold a finished print for $12."
    return true
end

function Shop.buyPlasticWrapRoll(state)
    if state.money < 20 then
        state.message = "Not enough money for a plastic wrap roll."
        return false
    end
    local inventory = state.inventory
    state.money = state.money - 20
    inventory.plasticWrapRolls = (inventory.plasticWrapRolls or 0) + 1
    if (inventory.plasticWrapUses or 0) == 0 then inventory.plasticWrapUses = 11 end
    state.message = "Bought one plastic wrap roll for $20. Each roll wraps 11 pallets."
    return true
end

function Shop.keypressed(key, state)
    if key == "1" then
        return Shop.buyPaper(state)
    elseif key == "2" then
        return Shop.sellPrint(state)
    end
    return false
end

return Shop
