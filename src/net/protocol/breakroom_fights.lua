-- Bounded realtime Critter Kombat state, never part of a durable shop save.
local Component={}
function Component.install(Runtime)
    local actions={idle=true,walk=true,jump=true,punch=true,kick=true,block=true,
        hit=true,knockout=true,victory=true}
    local function fighter(value,label)
        local okay,err=Runtime.shape(value,label,
            {"x","z","face","health","action","actionTime","wins"})
        if not okay then return nil,err end
        for _,field in ipairs({"x","z","health","actionTime"}) do
            local minimum,maximum=0,field=="x" and 800 or field=="z" and 300
                or field=="health" and 100 or 120
            local number,numberError=Runtime.numberInRange(value[field],minimum,maximum,label.."."..field)
            if number==nil then return nil,numberError end
        end
        if value.face~=1 and value.face~=-1 or not actions[value.action] then
            return nil,label.." pose is invalid"
        end
        local wins,winsError=Runtime.integerInRange(value.wins,0,2,label..".wins")
        if not wins then return nil,winsError end
        return value
    end
    function Runtime.normalizeFightSnapshot(payload)
        local okay,err=Runtime.shape(payload,"fight_snapshot payload",
            {"sessionId","serverTick","matches"})
        if not okay then return nil,err end
        local sessionId;sessionId,err=Runtime.token(payload.sessionId,Runtime.MAX_TOKEN_BYTES,
            "fight_snapshot.sessionId")
        if not sessionId then return nil,err end
        local tick;tick,err=Runtime.integerInRange(payload.serverTick,0,Runtime.UINT32_MAX,
            "fight_snapshot.serverTick")
        if not tick then return nil,err end
        if not Runtime.Codec.isArray(payload.matches) or #payload.matches>2 then
            return nil,"fight_snapshot.matches must have at most two matches"
        end
        local seen,matches={},{}
        for index,match in ipairs(payload.matches) do
            local label="fight_snapshot.matches["..index.."]"
            okay,err=Runtime.shape(match,label,
                {"bayId","mode","phase","leftId","round","seconds","left","right"},
                {"rightId"})
            if not okay then return nil,err end
            if not require("src.breakroom_games").BAYS[match.bayId] or seen[match.bayId]
                or (match.mode~="solo" and match.mode~="versus")
                or (match.phase~="waiting" and match.phase~="playing"
                    and match.phase~="round_over" and match.phase~="finished") then
                return nil,label.." identity is invalid"
            end
            seen[match.bayId]=true
            for _,field in ipairs({"leftId","rightId"}) do
                if match[field]~=nil then
                    local id,idErr=Runtime.integerInRange(match[field],1,Runtime.Protocol.MAX_PLAYERS,
                        label.."."..field)
                    if not id then return nil,idErr end
                end
            end
            local round,roundErr=Runtime.integerInRange(match.round,1,5,label..".round")
            if not round then return nil,roundErr end
            local seconds,timeErr=Runtime.numberInRange(match.seconds,0,60,label..".seconds")
            if seconds==nil then return nil,timeErr end
            local _,leftErr=fighter(match.left,label..".left")
            if leftErr then return nil,leftErr end
            local _,rightErr=fighter(match.right,label..".right")
            if rightErr then return nil,rightErr end
            matches[index]=match
        end
        return {sessionId=sessionId,serverTick=tick,matches=Runtime.Codec.array(matches)}
    end
end
return Component
