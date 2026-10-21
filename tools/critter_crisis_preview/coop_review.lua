local Review={}
function Review.run(runtime,Screen,Crisis,Arcade,destination)
    local report=assert(io.open(destination..'/review.txt','w'))
    local count=0
    local function check(name,ok,detail)
        assert(ok,name..': '..tostring(detail or 'failed'))
        count=count+1;report:write('PASS '..name..'\n');report:flush()
    end
    local function capture(name)
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push('all');love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(0,0,0,1)
        Screen.draw(runtime);love.graphics.pop()
        local pixels=canvas:newImageData();local encoded=pixels:encode('png')
        local file=assert(io.open(destination..'/'..name..'.png','wb'));file:write(encoded:getString());file:close()
        pixels:release();canvas:release();encoded:release()
    end
    local function step(seconds,inputs)
        for _=1,math.ceil(seconds*60) do Crisis.update(1/60,inputs or function()return {buttons=2}end) end
    end
    local Wire=require('src.critter_crisis_wire')
    local Protocol=require('src.net.protocol')
    local Inputs=require('src.critter_crisis_inputs')
    capture('01-menu')
    for _,kind in ipairs({'mission','range','stand','train'}) do
        Crisis.clear();Screen.enter()
        if kind=='mission' then Screen.keypressed(runtime,'7')
        else Screen.keypressed(runtime,({range='4',stand='5',train='6'})[kind]);capture(kind..'-modes');Screen.keypressed(runtime,'2') end
        local s=Crisis.sessions.front_left
        check(kind..' starts with two local players',s and s.mode=='local' and s.partnerId==0 and s.players[0])
        step(1.5);step(.4,function()return {}end)
        capture(kind..'-local')
        check(kind..' header encodes',Protocol.encode('crisis_snapshot',{sessionId='TEST',serverTick=1,bayId=s.bayId,session=Crisis.snapshot()[1]}))
        if kind~='mission' then
            local parts,err=Wire.parts(s);check(kind..' frame serializes',parts,err)
            local frame,decodeError=Wire.decode(table.concat(parts));check(kind..' frame decodes',frame,decodeError)
            local store={};local assembled
            for i=#parts,1,-1 do
                local payload={sessionId='TEST',serverTick=5,roundId=s.roundId,bayId=s.bayId,part=i,total=#parts,data=parts[i]}
                local encoded,encodeError=Protocol.encode('crisis_frame',payload)
                check(kind..' shard '..i..' fits packet',encoded and #encoded<=1200,encodeError)
                local nextFrame=Wire.accept(store,assert(Protocol.decode(encoded)).payload,0)
                if i>1 then check(kind..' incomplete frame stays private '..i,not nextFrame) else assembled=nextFrame end
            end
            check(kind..' reordered frame assembles',assembled and assembled.kind==kind)
            local duplicate={sessionId='TEST',serverTick=5,roundId=s.roundId,bayId=s.bayId,part=1,total=#parts,data=parts[1]}
            check(kind..' duplicate frame is ignored',not Wire.accept(store,duplicate,0))
            duplicate.serverTick=6;Wire.accept(store,duplicate,0)
            duplicate.serverTick=7
            local recovered
            for i,data in ipairs(parts)do duplicate.part=i;duplicate.data=data;recovered=Wire.accept(store,duplicate,.1) or recovered end
            check(kind..' next complete frame recovers after packet loss',recovered and recovered.kind==kind)
            local original=runtime.multiplayer
            local header=Crisis.snapshot()[1]
            runtime.multiplayer={isClient=function()return true end,crisisSnapshot=function()return {header}end,crisisFrontier=function()return assembled end}
            capture(kind..'-guest-local')
            header.mode='coop';header.partnerId=2;header.players[2].id=2
            runtime.World.player.id=2;capture(kind..'-guest-lan');runtime.World.player.id=1;runtime.multiplayer=original
        end
        Screen.arcadeInputs(runtime)
        Screen.keypressed(runtime,'lctrl');Screen.keypressed(runtime,'rshift')
        local a=Screen.arcadeInputs(runtime)
        check(kind..' keyboard keeps fire and partner cover separate',a.buttons==1 and a.buttons2==2)
        Screen.keyreleased('rshift');a=Screen.arcadeInputs(runtime)
        check(kind..' partner release preserves first trigger',a.buttons==1 and a.buttons2==0)
        Screen.focus(false);a=Screen.arcadeInputs(runtime)
        check(kind..' focus clears both players',a.buttons==0 and a.buttons2==0)
        Screen.focus(true);Screen.keyreleased('lctrl')
        local pad={axes={},connected=true,isConnected=function(self)return self.connected end,getGamepadAxis=function(self,key)return self.axes[key] or 0 end}
        Screen.gamepadpressed(runtime,pad,'a');a=Screen.arcadeInputs(runtime)
        check(kind..' first controller drives player two',a.buttons2==1 and a.buttons==0)
        Screen.gamepadreleased(pad,'a');Inputs.update(0);pad.axes.triggerright=1;Inputs.update(0)
        check(kind..' second controller trigger works',Screen.arcadeInputs(runtime).buttons2==1)
        Screen.focus(false);Screen.focus(true);Inputs.update(0)
        check(kind..' held controller trigger waits for release after focus',Screen.arcadeInputs(runtime).buttons2==0)
        pad.axes.triggerright=0;Inputs.update(0);pad.axes.triggerright=1;Inputs.update(0)
        check(kind..' controller trigger rearms',Screen.arcadeInputs(runtime).buttons2==1)
        pad.connected=false;Inputs.update(0)
        check(kind..' controller disconnect releases trigger',Screen.arcadeInputs(runtime).buttons2==0)
        local viewport=runtime.Viewport;runtime.Viewport={toGame=function(x,y)return x,y end}
        local by=kind=='mission' and 639 or 580
        Screen.touchpressed(runtime,'left-fire',40,by);Screen.touchpressed(runtime,'right-cover',kind=='mission' and 655 or 610,by)
        a=Screen.arcadeInputs(runtime)
        check(kind..' simultaneous touch controls address separate seats',a.buttons==1 and a.buttons2==2)
        Screen.touchreleased('left-fire');a=Screen.arcadeInputs(runtime)
        check(kind..' one touch release preserves other player cover',a.buttons==0 and a.buttons2==2)
        Screen.touchreleased('right-cover');runtime.Viewport=viewport
        step(.4,function()return {}end)
        local p1,p2=s.players[1],s.players[0]
        local ammo1,ammo2=p1.ammo,p2.ammo
        step(.02,function(id)return {x=-.5,y=-.2,buttons=id==0 and 1 or 0}end)
        check(kind..' player two has an independent trigger',p2.ammo==ammo2-1 and p1.ammo==ammo1,p2.ammo..' / '..ammo2)
        step(.4,function()return {}end)
        step(.02,function(id)return {x=.5,y=-.2,buttons=id==1 and 1 or 0}end)
        check(kind..' player one has an independent trigger',p1.ammo==ammo1-1,p1.ammo..' / '..ammo1)
        step(.02,function(id)return {buttons=id==0 and 4 or 0}end)
        check(kind..' reload belongs to player two',p2.reload>0 and p1.reload==0)
        step(10,function()return {buttons=2}end)
        check(kind..' player two reload completes',p2.reload==0)
        if kind~='mission' then
            local f=s.frontier
            local weapon1=kind=='range' and f.pilots[1].range.weapon or f.pilots[1].gun.weapon
            local weapon2=kind=='range' and f.pilots[2].range.weapon or f.pilots[2].gun.weapon
            step(.02,function(id)return {buttons=id==0 and 16 or 0}end)
            check(kind..' player two changes their own weapon',(kind=='range' and f.pilots[2].range.weapon or f.pilots[2].gun.weapon)~=weapon2
                and (kind=='range' and f.pilots[1].range.weapon or f.pilots[1].gun.weapon)==weapon1)
        end
        Crisis.prune({[1]=runtime.World.player})
        check(kind..' synthetic second seat survives pruning',Crisis.sessions.front_left==s)
        s.phase='finished';local round=s.roundId;Screen.keypressed(runtime,'return');s=Crisis.sessions.front_left
        check(kind..' restart keeps both seats',s.mode=='local' and s.players[0] and s.roundId>round)
        if kind=='mission' then
            local stages=0
            while s.phase=='playing' and stages<15 do
                for _,enemy in ipairs(s.enemies)do enemy.hp=0 end
                if stages==0 then s.players[0].hp=0 end
                step(1.3);stages=stages+1
                if stages==1 then check('partner revives at next mission checkpoint',s.players[0].hp==3) end
            end
            check('all fourteen mission stages support both players',stages==14 and s.phase=='finished' and s.players[0] and s.players[1])
        elseif kind=='range' then
            s.frontier.world.time=.01;step(.02)
            check('range produces results for both players',s.phase=='finished' and s.frontier.pilots[1].range.result and s.frontier.pilots[2].range.result)
        elseif kind=='stand' then
            local f=s.frontier;f.world.elapsed=44.99;step(.03,function()return {}end)
            check('Last Stand enters shared wave intermission',f.world.result=='intermission')
            f.pilots[1].data.health=0
            step(.02,function(id)return {buttons=id==0 and 64 or 0}end)
            check('player two advances wave and revives partner',not f.world.result and f.pilots[1].data.health==10)
            f.world.elapsed=181;f.world.stage=4;f.objective.completedPhase=3;f.objective.kills=15;f.objective.enemyMorale=0
            step(.02,function()return {}end);step(5.2)
            check('Last Stand completes for the team',s.phase=='finished')
        else
            local f=s.frontier
            for _,v in ipairs(f.world.vehicles)do v.hull=0 end
            f.world.phase='combat';step(2.2)
            check('train convoy defeat completes for the team',s.phase=='finished')
        end
        capture(kind..'-complete')
        Screen.leave(runtime);check(kind..' leave releases cabinet',not Crisis.sessions.front_left)
    end
    -- A shared target takes both players' hits, while cover protects only its owner.
    Crisis.clear();assert(Screen.command(runtime,'start_range_local'))
    local shared=Crisis.sessions.front_left;step(.2,function()return {}end)
    local target=shared.frontier.world.targets[1]
    Crisis.update(0,function()return {x=(target.x-480)/480,y=(target.y-360)/360,buttons=1}end)
    check('both range views share the same hit target',target.hit and shared.frontier.pilots[2].range.targets[1]==target)
    check('simultaneous range hit scores target once',shared.frontier.pilots[1].range.hits+shared.frontier.pilots[2].range.hits==1)
    Crisis.clear();assert(Screen.command(runtime,'start_stand_local'));shared=Crisis.sessions.front_left
    local f=shared.frontier;local scene=require('src.arcade_frontier.window_scene')
    local target=f.world.targets[1];target.status='exposed';target.health=3;target.maxHealth=3;target.timer=1
    local x,y=scene.slotPosition(scene.layout('wide',960,720),target.slot)
    Crisis.update(0,function()return {x=(x-480)/480,y=(y-360)/360,buttons=1}end)
    check('two Last Stand shots damage one shared enemy',target.health==1,target.health)
    step(.4,function(id)return {buttons=id==1 and 2 or 0}end)
    target.status='firing';target.fired=false;target.timer=.16;target.heavy=false
    local random=love.math.random;love.math.random=function()return 0 end
    Crisis.update(.01,function(id)return {buttons=id==1 and 2 or 0}end);love.math.random=random
    check('Last Stand cover protects only the covered player',f.pilots[1].data.health==20 and f.pilots[2].data.health==19)
    Crisis.clear();Screen.enter()
    require('tools.critter_crisis_preview.lan_review').run(check)
    report:write('ALL '..count..' CHECKS PASSED\n');report:close()
end
return Review
