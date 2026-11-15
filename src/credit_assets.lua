-- Vehicle and forklift offers share the equipment lender's account terms.
local Dealer=require('src.vehicle_dealer')
local Assets={ORDER={'box_new','box_used','kei_new','kei_used','forklift'}}
function Assets.offer(id)
    if id=='forklift' then
        local offer=require('src.warehouse_upgrades').catalog('forklift')
        offer.id='forklift';offer.model='forklift';offer.assetKind='forklift';offer.condition='new'
        return offer
    end
    local offer=Dealer.listing(id)
    if offer then offer.assetKind='vehicle' end
    return offer
end
function Assets.owned(state,offer)
    if offer.assetKind=='forklift' then return state.warehouse and state.warehouse.forkliftOwned==true end
    return Dealer.owns(state,offer.model)
end
function Assets.validLoan(loan)
    local offer=Assets.offer(loan.listingId)
    return offer~=nil and loan.assetKind==offer.assetKind and loan.assetId==offer.model
        and loan.modelId==offer.model and loan.machineId==nil and loan.channel=='fleet'
end
function Assets.purchase(state,offer,requestId,payment)
    if offer.assetKind=='forklift' then
        return require('src.warehouse_upgrades').purchaseForklift(state,requestId,nil,payment)
    end
    return Dealer.purchase(state,offer.id,requestId,nil,payment)
end
return Assets
