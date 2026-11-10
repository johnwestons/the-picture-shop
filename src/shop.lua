local Shop = {}

function Shop.buyPaper(state)
    if state.money < 25 then
        state.message = "Not enough money."
        return false
    end
    require("src.household_finances").purchase(state,"abstract_paper",25,2500)
    state.money = state.money - 25
    require('src.receipt_book').expense(state,'Paper purchase',2500,'Shop supplies','Shop','25 sheets of paper')
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
    require('src.receipt_book').add(state,{kind='job',title='Finished print sale',party='Retail customer',amountCents=1200,details='One finished print.'})
    require("src.household_finances").record(state,"revenue",1200)
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
