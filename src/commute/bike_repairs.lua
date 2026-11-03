-- Collision repairs belong to the owner of the motorcycle parked at the shop.
local Upgrades = require('src.commute.bike_upgrades')
local Residents = require('src.home_residents')
local Repairs = { CENTS_PER_POINT = 200, MAX_REVISION = 1000000000000 }

function Repairs.validRevision(value)
    return type(value) == 'number' and value >= 0 and value <= Repairs.MAX_REVISION and value % 1 == 0
end

function Repairs.validQuotedDamage(value)
    return type(value) == 'number' and value >= 1 and value <= 100 and value % 1 == 0
end

function Repairs.quote(state, player)
    local resident = Residents.get(state, player)
    if not resident then return nil end
    local damage = resident.ridingDamage or 0
    local revision = resident.ridingRepairRevision or 0
    if damage ~= 0 and not Repairs.validQuotedDamage(damage) or not Repairs.validRevision(revision) then return nil end
    local price = damage * Repairs.CENTS_PER_POINT
    local shortfall = math.max(0, price - state.home.balanceCents)
    return {
        damage = damage, revision = revision, condition = 100 - damage,
        priceCents = price, shortfallCents = shortfall,
        status = damage == 0 and 'healthy' or shortfall > 0 and 'unaffordable' or 'available',
    }
end

function Repairs.purchase(state, player, trip, world, intent)
    if type(intent) ~= 'table' or not trip or intent.token ~= trip.token then return false, 'That ride has ended.' end
    if not Repairs.validRevision(intent.expectedRepairRevision) or not Repairs.validQuotedDamage(intent.expectedDamage) then
        return false, 'Review the current repair estimate.'
    end
    local okay, message, resident, bike = Upgrades.canVisit(state, player, trip, world)
    if not okay then return false, message end
    local quote = Repairs.quote(state, player)
    if not quote or quote.damage ~= (bike.damage or 0) then return false, 'The bike condition record is out of sync.' end
    if quote.revision ~= intent.expectedRepairRevision or quote.damage ~= intent.expectedDamage then
        return false, 'Your bike condition changed. Review the updated estimate.'
    end
    if quote.revision >= Repairs.MAX_REVISION then return false, 'The repair record cannot accept another order.' end
    if quote.status ~= 'available' then return false, 'Not enough household money for this repair.' end
    state.home.balanceCents = state.home.balanceCents - quote.priceCents
    bike.damage = 0
    resident.ridingDamage = 0
    resident.ridingRepairRevision = quote.revision + 1
    resident.revision = resident.revision + 1
    state.home.revision = state.home.revision + 1
    return true, 'Bike repaired. Full performance restored.'
end

return Repairs
