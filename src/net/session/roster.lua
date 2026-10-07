-- Player rosters and runtime identifiers.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Session:_records()
        local ids = {}
        for id in pairs(self.players) do ids[#ids + 1] = id end
        table.sort(ids)
        local records = {}
        for _, id in ipairs(ids) do records[#records + 1] = Runtime.playerRecord(self.players[id]) end
        return records
    end

    function Runtime.Session:_syncLocalPlayer(localPlayer)
        local player = self.localId and self.players[self.localId]
        if not player or not localPlayer then return end
        Runtime.copyMotion(player, localPlayer, true)
        player.name = self.localName or player.name
        player.character = localPlayer.character or self.localCharacter or player.character
    end

    function Runtime.Session:_nextPlayerId()
        for index = 2, Runtime.Protocol.MAX_PLAYERS do
            if not self.players[index] then return index, index end
        end
    end

    function Runtime.Session:_nextRuntimeHandle(field)
        local current = self[field]
        if type(current) ~= "number" or current ~= math.floor(current)
            or current < 0 or current >= 9007199254740991
        then
            return nil
        end
        current = current + 1
        self[field] = current
        return current
    end
end

return Component
