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

function Shop.keypressed(key, state)
    if key == "1" then
        return Shop.buyPaper(state)
    elseif key == "2" then
        return Shop.sellPrint(state)
    end
    return false
end

return Shop
