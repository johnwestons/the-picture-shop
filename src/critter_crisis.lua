-- Host-owned, temporary light-gun arcade game. No shop save fields are used.
local Games=require("src.breakroom_games")
local Enemy=require("src.critter_crisis_enemy")
local Crisis={sessions={}}
Crisis.GAMES={mission=true}
Crisis.FIRE,Crisis.COVER,Crisis.RELOAD=1,2,4
Crisis.ROUTES={
    {name="NEON TRANSIT YARD",stops={"CARGO GATE","PLATFORM","SKYBRIDGE","LIFT"}},
    {name="REACTOR TOWER",stops={"SERVICE LIFT","COOLANT HALL","CORE","ROOFTOP"}},
    {name="FLOODLIGHT DOCKS",stops={"DOCK GATE","CRANES","BOARD BOAT","CHANNEL","FLOODGATE","BREAKWATER"}},
}
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
local function held(mask,bit) return math.floor((mask or 0)/bit)%2==1 end
local function near(player,fixture)
    return (player.x-fixture.interactionX)^2+(player.y-fixture.interactionY)^2<=80^2
end
local function playerState(id)
    return {id=id,hp=5,ammo=8,covered=false,reload=0,cooldown=0,previous=0,aimX=480,aimY=310,shot=0}
end
local function stage(session)
    session.enemies={};session.barrels={};session.transition=0;session.elapsed=0
    local level,stop=session.level,session.stop
    local count=2+((level+stop)%2)
    for i=1,count do
        session.enemies[i]=Enemy.new(i,level,stop)
    end
    session.barrels[1]={x=360+(stop%2)*255,y=445,alive=true}
    if level==3 and stop>=4 then
        -- A second fuel drum makes the moving boat encounter distinct.
        session.barrels[2]={x=715,y=412,alive=true}
    end
end
local function newSession(bay,id,mode,game)
    Crisis.nextRound=(Crisis.nextRound or 0)+1
    local s={bayId=bay,ownerId=id,partnerId=nil,mode=mode,phase=mode=="coop" and "waiting" or "playing",
        game=game or 'mission',roundId=Crisis.nextRound,
        level=1,stop=1,score=0,elapsed=0,transition=0,flash=0,hit=0,
        players={[id]=playerState(id)}}
    if mode=='local' then s.partnerId=0;s.players[0]=playerState(0) end
    if s.game=='mission' then stage(s)
    else s.enemies={};s.barrels={};s.frontier=require('src.critter_crisis_frontier').new(s.game) end
    return s
end
function Crisis.startAction(action)
    if action=='start_solo' then return 'mission','solo' end
    if action=='start_coop' then return 'mission','coop' end
    if type(action)~='string' then return end
    local game,mode=action:match('^start_(%a+)_(%a+)$')
    if Crisis.GAMES[game] and mode=='coop' then return game,mode end
end
function Crisis.command(state,player,action)
    local bay=player and player.sceneId
    if not Games.BAYS[bay] or not Games.owns(state,bay,"critter_kombat") then
        return false,"room_locked","There is no arcade cabinet here."
    end
    if not near(player,Games.CATALOG.critter_kombat) then
        return false,"out_of_range","Stand at the arcade cabinet."
    end
    local id=tonumber(player.id) or 1
    local s=Crisis.sessions[bay]
    local game,mode=Crisis.startAction(action)
    if game then
        local fight=require("src.critter_kombat").matches[bay]
        if fight and fight.phase~="finished" or s and s.phase~="finished" and s.phase~="failed" then
            return false,"cabinet_busy","The arcade cabinet is already in use."
        end
        if fight then require("src.critter_kombat").matches[bay]=nil end
        Crisis.sessions[bay]=newSession(bay,id,mode,game)
        return true,"accepted",mode=='coop' and 'Waiting for the second player to join this cabinet.' or 'Arcade game started!'
    elseif action=="join" then
        if not s or s.phase~="waiting" or s.ownerId==id or s.partnerId then
            return false,"not_joinable","No open co-op mission at this cabinet."
        end
        s.partnerId=id;s.players[id]=playerState(id);s.phase="playing"
        return true,"accepted","Co-op mission started!"
    elseif action=="restart" then
        if not s or s.ownerId~=id or s.phase~="finished" and s.phase~="failed" then
            return false,"not_finished","Only the host player can restart a completed mission."
        end
        local fresh=newSession(bay,id,s.mode,s.game)
        if s.partnerId then fresh.partnerId=s.partnerId;fresh.players[s.partnerId]=playerState(s.partnerId);fresh.phase="playing" end
        Crisis.sessions[bay]=fresh
        return true,"accepted","Mission restarted."
    elseif action=="leave" then
        if s and (s.ownerId==id or s.partnerId==id) then Crisis.sessions[bay]=nil end
        return true,"accepted","Critter Crisis ended."
    end
    return false,"not_allowed","Unknown arcade action."
end
local function blast(s,barrel)
    barrel.alive=false;s.flash=.42;s.score=s.score+30
    for _,enemy in ipairs(s.enemies) do
        if enemy.hp>0 and math.abs(enemy.x-barrel.x)<235 and math.abs(enemy.y-barrel.y)<210 then
            enemy.hp=0;s.score=s.score+100
        end
    end
end
local function shoot(s,p)
    if p.hp<=0 or p.covered or p.reload>0 or p.cooldown>0 or p.ammo<1 then return end
    p.ammo=p.ammo-1;p.cooldown=.27;p.shot=.12
    local target,depth,barrelHit=nil,-1,false
    for _,barrel in ipairs(s.barrels) do
        local b=Enemy.barrel(barrel)
        if barrel.alive and b.depth>depth and p.aimX>=b.left and p.aimX<=b.right and p.aimY>=b.top and p.aimY<=b.bottom
            and not Enemy.occluded(s,{y=b.depth},p.aimX,p.aimY) then
            target=barrel;depth=b.depth;barrelHit=true
        end
    end
    for _,enemy in ipairs(s.enemies) do
        if enemy.y>depth and Enemy.hittable(s,enemy,p.aimX,p.aimY) then
            target=enemy;depth=enemy.y;barrelHit=false
        end
    end
    if barrelHit then blast(s,target)
    elseif target then
        target.hp=target.hp-1;s.hit=.15
        if target.hp==0 then s.score=s.score+100 end
    end
end
local function advance(s)
    if s.stop<#Crisis.ROUTES[s.level].stops then s.stop=s.stop+1
    elseif s.level<#Crisis.ROUTES then s.level=s.level+1;s.stop=1
    else s.phase="finished";s.score=s.score+500;return end
    stage(s)
    for _,p in pairs(s.players) do if p.hp<=0 then p.hp=3;p.ammo=8;p.reload=0 end end
end
function Crisis.update(dt,inputFor)
    dt=clamp(dt or 0,0,.1)
    for _,s in pairs(Crisis.sessions) do
        if s.phase=="playing" then
            if s.game~='mission' and s.frontier then
                require('src.critter_crisis_frontier').update(s,dt,inputFor)
            else
            s.elapsed=s.elapsed+dt;s.flash=math.max(0,s.flash-dt);s.hit=math.max(0,s.hit-dt)
            for _,p in pairs(s.players) do
                local input=inputFor and inputFor(p.id,s) or nil
                local buttons=input and input.buttons or 0
                local pressed=require('src.critter_crisis_actions').consume(p,input)
                if input then
                    p.aimX=clamp(480+(input.x or 0)*480,40,920)
                    p.aimY=clamp(339+(input.y or 0)*339,105,560)
                end
                p.covered=held(buttons,Crisis.COVER)
                p.cooldown=math.max(0,p.cooldown-dt);p.shot=math.max(0,(p.shot or 0)-dt)
                if held(pressed,Crisis.RELOAD) and p.ammo<8 then
                    p.reload=1.15
                end
                if p.reload>0 then
                    p.reload=math.max(0,p.reload-dt)
                    if p.reload==0 then p.ammo=8 end
                end
                if held(pressed,Crisis.FIRE) then shoot(s,p) end
                p.previous=buttons
            end
            for _,enemy in ipairs(s.enemies) do Enemy.update(enemy,s,dt) end
            local alive=false;for _,enemy in ipairs(s.enemies) do if enemy.hp>0 then alive=true;break end end
            if not alive then s.transition=s.transition+dt;if s.transition>=1.25 then advance(s) end end
            local living=false;for _,p in pairs(s.players) do if p.hp>0 then living=true end end
            if not living then s.phase="failed" end
            end
        end
    end
end
function Crisis.prune(players)
    for bay,s in pairs(Crisis.sessions) do
        local owner=players[s.ownerId]
        local partner=s.partnerId and players[s.partnerId]
        if not owner or owner.sceneId~=bay or s.mode~='local' and s.partnerId and (not partner or partner.sceneId~=bay) then
            Crisis.sessions[bay]=nil
        end
    end
end
local function rounded(n) return math.floor(n*10+.5)/10 end
function Crisis.snapshot()
    local array=require('src.net.codec').array
    local out={}
    for _,bay in ipairs({"front_left","front_right"}) do
        local s=Crisis.sessions[bay]
        if s then
            local players={};for _,p in pairs(s.players) do players[#players+1]={id=p.id,hp=p.hp,ammo=p.ammo,
                covered=p.covered,reload=rounded(p.reload),aimX=rounded(p.aimX),aimY=rounded(p.aimY),shot=rounded(p.shot or 0)} end
            local enemies={};for _,e in ipairs(s.enemies) do enemies[#enemies+1]={x=rounded(e.x),y=rounded(e.y),hp=e.hp,
                kind=e.kind,mode=e.mode,shot=rounded(e.shot),posture=math.floor(e.posture*1000+.5)/1000,
                travel=rounded(e.travel),coverId=e.coverId} end
            local barrels={};for _,b in ipairs(s.barrels) do barrels[#barrels+1]={x=b.x,y=b.y,alive=b.alive} end
            out[#out+1]={bayId=bay,ownerId=s.ownerId,partnerId=s.partnerId,mode=s.mode,phase=s.phase,game=s.game or 'mission',roundId=s.roundId,
                level=s.level,stop=s.stop,score=s.score,transition=rounded(s.transition),flash=rounded(s.flash),
                players=array(players),enemies=array(enemies),barrels=array(barrels)}
        end
    end
    return out
end
function Crisis.clear() Crisis.sessions={} end
return Crisis
