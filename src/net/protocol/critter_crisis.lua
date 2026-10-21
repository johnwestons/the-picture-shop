-- Bounded, one-bay-at-a-time snapshots for the temporary arcade shooter.
local Component={}
function Component.install(Runtime)
    local function integer(v,a,b,label)
        local n,err=Runtime.integerInRange(v,a,b,label)
        if not n then return nil,err end
        return true
    end
    local function number(v,a,b,label)
        local n,err=Runtime.numberInRange(v,a,b,label)
        if n==nil then return nil,err end
        return true
    end
    local function array(v,max,label)
        if not Runtime.Codec.isArray(v) or #v>max then return nil,label.." is invalid" end
        return true
    end
    function Runtime.normalizeCrisisSnapshot(payload)
        local ok,err=Runtime.shape(payload,"crisis_snapshot payload",{"sessionId","serverTick","bayId","session"})
        if not ok then return nil,err end
        local sessionId;sessionId,err=Runtime.token(payload.sessionId,Runtime.MAX_TOKEN_BYTES,"crisis_snapshot.sessionId")
        if not sessionId then return nil,err end
        ok,err=integer(payload.serverTick,0,Runtime.UINT32_MAX,"crisis_snapshot.serverTick")
        if not ok then return nil,err end
        if not require("src.breakroom_games").BAYS[payload.bayId] then return nil,"crisis_snapshot.bayId is invalid" end
        local s=payload.session
        if s==false then return {sessionId=sessionId,serverTick=payload.serverTick,bayId=payload.bayId,session=false} end
        ok,err=Runtime.shape(s,"crisis_snapshot.session",
            {"bayId","ownerId","mode","phase","game","roundId","level","stop","score","transition","flash","players","enemies","barrels"},
            {"partnerId"})
        if not ok then return nil,err end
        if s.bayId~=payload.bayId or not ({solo=true,coop=true,['local']=true})[s.mode]
            or not require('src.critter_crisis').GAMES[s.game]
            or not ({waiting=true,playing=true,finished=true,failed=true})[s.phase] then
            return nil,"crisis_snapshot session identity is invalid"
        end
        for _,field in ipairs({{"roundId",1,Runtime.UINT32_MAX},{"ownerId",1,Runtime.Protocol.MAX_PLAYERS},{"level",1,3},
            {"stop",1,s.level==3 and 6 or 4},{"score",0,1000000}}) do
            ok,err=integer(s[field[1]],field[2],field[3],"crisis_snapshot."..field[1]);if not ok then return nil,err end
        end
        if s.partnerId~=nil then
            ok,err=integer(s.partnerId,s.mode=='local' and 0 or 1,Runtime.Protocol.MAX_PLAYERS,"crisis_snapshot.partnerId")
            if not ok or s.partnerId==s.ownerId then return nil,err or "duplicate partner" end
        end
        if s.mode=='local' and s.partnerId~=0 then return nil,'local partner must be seat two' end
        for _,field in ipairs({{"transition",0,2},{"flash",0,1}}) do
            ok,err=number(s[field[1]],field[2],field[3],"crisis_snapshot."..field[1]);if not ok then return nil,err end
        end
        ok,err=array(s.players,2,"crisis_snapshot.players");if not ok or #s.players<1 then return nil,err or "missing player" end
        ok,err=array(s.enemies,3,"crisis_snapshot.enemies");if not ok then return nil,err end
        ok,err=array(s.barrels,2,"crisis_snapshot.barrels");if not ok then return nil,err end
        local seen={}
        for i,p in ipairs(s.players) do
            local label="crisis_snapshot.players["..i.."]"
            ok,err=Runtime.shape(p,label,{"id","hp","ammo","covered","reload","aimX","aimY","shot"})
            if not ok then return nil,err end
            for _,f in ipairs({{"id",s.mode=='local' and 0 or 1,Runtime.Protocol.MAX_PLAYERS},{"hp",0,5},{"ammo",0,s.game=='mission' and 8 or 40}}) do
                ok,err=integer(p[f[1]],f[2],f[3],label.."."..f[1]);if not ok then return nil,err end
            end
            if seen[p.id] or (p.id~=s.ownerId and p.id~=s.partnerId) or type(p.covered)~="boolean" then
                return nil,label.." identity is invalid"
            end
            seen[p.id]=true
            for _,f in ipairs({{"reload",0,1.2},{"aimX",0,960},{"aimY",0,678},{"shot",0,.2}}) do
                ok,err=number(p[f[1]],f[2],f[3],label.."."..f[1]);if not ok then return nil,err end
            end
        end
        if not seen[s.ownerId] or s.partnerId~=nil and not seen[s.partnerId] then return nil,'missing arcade participant' end
        for i,e in ipairs(s.enemies) do
            local label="crisis_snapshot.enemies["..i.."]"
            ok,err=Runtime.shape(e,label,{"x","y","hp","kind","mode","shot","posture","travel","coverId"})
            if not ok then return nil,err end
            for _,f in ipairs({{"x",0,960},{"y",0,678},{"shot",0,.3},{"posture",0,1},{"travel",0,10000}}) do
                ok,err=number(e[f[1]],f[2],f[3],label.."."..f[1]);if not ok then return nil,err end
            end
            for _,f in ipairs({{"hp",0,2},{"kind",1,4},{"coverId",1,3*(2+((s.level+s.stop)%2))}}) do
                ok,err=integer(e[f[1]],f[2],f[3],label.."."..f[1]);if not ok then return nil,err end
            end
            if not require("src.critter_crisis_enemy").MODES[e.mode] then return nil,label.." mode is invalid" end
        end
        for i,b in ipairs(s.barrels) do
            local label="crisis_snapshot.barrels["..i.."]"
            ok,err=Runtime.shape(b,label,{"x","y","alive"});if not ok then return nil,err end
            for _,f in ipairs({"x","y"}) do
                ok,err=number(b[f],0,960,label.."."..f);if not ok then return nil,err end
            end
            if type(b.alive)~="boolean" then return nil,label..".alive is invalid" end
        end
        return {sessionId=sessionId,serverTick=payload.serverTick,bayId=payload.bayId,session=s}
    end
    function Runtime.normalizeCrisisFrame(payload)
        local ok,err=Runtime.shape(payload,'crisis_frame',{'sessionId','serverTick','roundId','bayId','part','total','data'})
        if not ok then return nil,err end
        local token;token,err=Runtime.token(payload.sessionId,Runtime.MAX_TOKEN_BYTES,'crisis_frame.sessionId')
        if not token then return nil,err end
        if not require('src.breakroom_games').BAYS[payload.bayId] then return nil,'invalid arcade bay' end
        for _,f in ipairs({{'serverTick',0,Runtime.UINT32_MAX},{'roundId',1,Runtime.UINT32_MAX},{'part',1,80},{'total',1,80}}) do
            ok,err=integer(payload[f[1]],f[2],f[3],'crisis_frame.'..f[1]);if not ok then return nil,err end
        end
        if payload.part>payload.total or type(payload.data)~='string' or #payload.data<1 or #payload.data>600 then return nil,'invalid arcade shard' end
        return payload
    end
end
return Component
