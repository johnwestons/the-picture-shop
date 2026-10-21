-- Play every encounter through ordinary aiming, firing, cover and reloading.
local Crisis=require('src.critter_crisis')
local Enemy=require('src.critter_crisis_enemy')
local Games=require('src.breakroom_games')
local Test={}
local function aimAtVisibleEnemy(session)
    for _,enemy in ipairs(session.enemies) do
        if enemy.hp>0 and enemy.posture>.9 then
            local body=Enemy.body(enemy)
            local x,y=enemy.x,body.top+12
            if Enemy.hittable(session,enemy,x,y) then return (x-480)/480,(y-339)/339 end
        end
    end
end
function Test.run(_,check)
    local previous,round=Crisis.sessions,Crisis.nextRound
    Crisis.sessions={}
    local state={breakroomGames=Games.defaultState()}
    state.breakroomGames.bays.front_left.critter_kombat=true
    local fixture=Games.CATALOG.critter_kombat
    local host={id=1,sceneId='front_left',x=fixture.interactionX,y=fixture.interactionY}
    local guest={id=2,sceneId=host.sceneId,x=host.x,y=host.y}
    for _,mode in ipairs({'solo','coop'}) do
        Crisis.clear()
        assert(Crisis.command(state,host,'start_'..mode))
        if mode=='coop' then assert(Crisis.command(state,guest,'join')) end
        local session=Crisis.sessions.front_left
        local visited={};local stageCount,shots,reloads=0,0,0
        for _=1,60*600 do
            local key=session.level..':'..session.stop
            if not visited[key] then visited[key]=true;stageCount=stageCount+1 end
            Crisis.update(1/60,function(id,s)
                local p=s.players[id]
                if p.ammo==0 and p.reload==0 then reloads=reloads+1;return {buttons=6} end
                if p.ammo>0 and p.reload==0 and p.cooldown<=0 then
                    local x,y=aimAtVisibleEnemy(s)
                    if x then shots=shots+1;return {x=x,y=y,buttons=1} end
                end
                return {buttons=2}
            end)
            if session.phase~='playing' then break end
        end
        for level,route in ipairs(Crisis.ROUTES) do
            local complete=true
            for stop=1,#route.stops do complete=complete and visited[level..':'..stop] end
            check('crisis_'..mode..'_completes_level_'..level,complete,route.name)
        end
        check('crisis_'..mode..'_wins_all_fourteen_encounters',stageCount==14 and session.phase=='finished')
        check('crisis_'..mode..'_uses_real_shots_and_reloads',shots>30 and reloads>0 and session.score>=4000)
        for id,p in pairs(session.players) do check('crisis_'..mode..'_player_'..id..'_survives',p.hp>0) end
    end
    Crisis.sessions,Crisis.nextRound=previous,round
end
return Test
