-- Player journeys through real controls and simulation, including interruption
-- and retry. Fixtures only establish the starting room and owned equipment.
local Test={}
local State=require('src.state')
local Grocery=require('src.commute.grocery_interior')
local Store=require('src.commute.town_store')
local Inventory=require('src.commute.grocery_inventory')
local Calendar=require('src.business_calendar')
local Schema=require('src.save_schema')

local function groceryRoutes(check)
    for _,shared in ipairs({false,true}) do
        local state=State.new();state.screen='world'
        if shared then state.home.commute={independent=true,participants={}} end
        local player={id=1,x=480,y=548,intentX=0,intentY=-1,sceneId='grocery',
            velocityX=0,velocityY=0,animationDistance=0,idleClock=0}
        local R={state=state,World={player=player},Config={baseWidth=960,baseHeight=678},
            Input={movement=function()return 0,0 end}}
        local view=Grocery.new(R)
        assert(Grocery.keypressed(view,'e')=='cartpush_on')
        player.cartPushing=true
        local failures={}
        local function visit(hotspot)
            local action=Grocery.pointer(view,R,hotspot.x,hotspot.y)
            for _=1,1800 do
                if action then break end
                action=Grocery.update(view,R,1/60)
                if shared then
                    Grocery.movePose(player,view.netInputX or 0,view.netInputY or 0,1/60,state)
                end
            end
            if action~=hotspot.id then
                failures[#failures+1]=('%s stopped at %.1f,%.1f (%d waypoints)'):format(
                    hotspot.id,view.pose.x,view.pose.y,view.path and #view.path or 0)
            end
        end
        for _,hotspot in ipairs(Grocery.hotspots) do visit(hotspot) end
        for _,origin in ipairs(Grocery.hotspots) do
            for _,destination in ipairs(Grocery.hotspots) do
                visit(origin);visit(destination)
            end
        end
        check('journey_grocery_cart_reaches_every_shelf_and_checkout_'..tostring(shared),
            #failures==0,table.concat(failures,'; '))
        visit(Grocery.hotspots[#Grocery.hotspots])
        check('journey_grocery_register_is_reachable_'..tostring(shared),Grocery.atCheckout(view.pose))
        Grocery.pointer(view,R,Grocery.hotspots[1].x,Grocery.hotspots[1].y)
        R.state.screen='options'
        local x,y=view.pose.x,view.pose.y
        Grocery.update(view,R,.1)
        check('journey_grocery_menu_pauses_cart_'..tostring(shared),view.pose.x==x and view.pose.y==y
            and view.netInputX==0 and view.netInputY==0)
        R.state.screen='world'
        visit(Grocery.hotspots[2])
        check('journey_grocery_changed_destination_reaches_new_shelf_'..tostring(shared),#failures==0,
            table.concat(failures,'; '))
        Grocery.keypressed(view,'f')
        check('journey_grocery_cart_returns_and_releases_control_'..tostring(shared),
            not view.pose.cartPushing and not view.cartPose.pushed and view.path==nil
            and view.cartPose.x==520 and view.cartPose.y==548)
    end
end

local function shoppingRecovery(check)
    local state=State.new();state.calendar.elapsed=9/24*Calendar.secondsPerDay(state)
    local stock=Inventory.ensure(state)
    local player={id=1}
    local rider={ped={x=1,z=2,crash=false},gear={mounted=false,transition=false}}
    local world={sites={byId={grocery={door={x=1,z=2}}}}}
    local intent={expectedRevision=state.home.revision,cart={bread=2,vegetables=1}}
    local bread=stock.stock.bread
    state.home.balanceCents=0
    local rejected=Store.purchaseCart(state,player,rider,world,intent)
    check('journey_grocery_no_funds_preserves_stock_and_revision',not rejected
        and stock.stock.bread==bread and state.home.revision==intent.expectedRevision)
    state.home.balanceCents=10000
    local accepted=Store.purchaseCart(state,player,rider,world,intent)
    local paidBalance=state.home.balanceCents
    local duplicate=Store.purchaseCart(state,player,rider,world,intent)
    check('journey_grocery_retry_pays_once_and_loads_exact_cargo',accepted and not duplicate
        and state.home.balanceCents==paidBalance and paidBalance==9000
        and stock.stock.bread==bread-2 and state.home.residents.owner.bikeInventory.items.bread==2)
    local restored=State.new()
    assert(State.applySharedSnapshot(restored,assert(Schema.snapshot(state))))
    check('journey_grocery_paid_cargo_survives_save',
        restored.home.residents.owner.bikeInventory.items.vegetables==1
        and restored.home.balanceCents==paidBalance and restored.groceryStore.stock.bread==bread-2)
    local Cargo=require('src.home_bike_cargo')
    restored.home.weekend.phase='home';restored.home.residents.owner.bikeParkedAtHome=true
    player.sceneId='home'
    local target=Cargo.target(player,restored)
    assert(target,'Home cargo target missing')
    player.x,player.y=target.x,target.y
    local before=restored.home.inventory.bread or 0
    local revision=restored.home.residents.owner.bikeInventory.revision
    local command='bike:all:'..revision
    local unloaded=Cargo.command(restored,player,command)
    local after=restored.home.inventory.bread or 0
    local again=Cargo.command(restored,player,command)
    check('journey_grocery_unloads_home_exactly_once',unloaded and not again
        and after>before and restored.home.inventory.bread==after
        and Cargo.used(restored.home.residents.owner.bikeInventory)==0)
end

local function hockeyJourney(check)
    local Hockey=require('src.air_hockey')
    local Games=require('src.breakroom_games')
    local Upgrades=require('src.warehouse_upgrades')
    local previous=Hockey.matches;Hockey.matches={}
    local ok,reason=xpcall(function()
        local state=State.new();state.money=50000
        for index,bay in ipairs({'front_left','front_right'}) do
            local project='WUP-000'..index
            assert(Upgrades.purchase(state,bay,'breakroom','JOURNEY-ROOM-'..index,0))
            Upgrades.update(state,0)
            Upgrades.update(state,0,{noticeDeliveredProjectId=project,noticeCallId='JOURNEY-CALL-'..index})
            Upgrades.update(state,2,{workerArrivedProjectId=project})
            Upgrades.update(state,98);Upgrades.update(state,98,{workerReleasedProjectId=project})
            assert(Games.purchase(state,bay,'air_hockey','JOURNEY-HOCKEY-'..index))
            local f=Games.CATALOG.air_hockey
            local p={id=1,sceneId=bay,x=f.interactionX,y=f.interactionY}
            assert(Hockey.command(state,p,'start_solo'))
            local match=Hockey.matches[bay]
            for _=1,60*600 do
                Hockey.update(1/60)
                if match.phase=='finished' then break end
            end
            check('journey_hockey_solo_reaches_seven_'..bay,match.phase=='finished'
                and math.max(match.leftScore,match.rightScore)==7,
                ('phase=%s score=%d:%d'):format(match.phase,match.leftScore,match.rightScore))
            local score=match.leftScore+match.rightScore
            Hockey.update(.2)
            check('journey_hockey_finished_match_stops_scoring_'..bay,score==match.leftScore+match.rightScore)
            assert(Hockey.command(state,p,'start_versus'))
            local second={id=2,sceneId=bay,x=p.x,y=p.y}
            assert(Hockey.command(state,second,'join'))
            check('journey_hockey_spectator_cannot_replace_opponent_'..bay,
                not Hockey.command(state,{id=3,sceneId=bay,x=p.x,y=p.y},'join'))
            Hockey.prune({[1]=p})
            check('journey_hockey_disconnect_releases_table_'..bay,Hockey.matches[bay]==nil)
            assert(Hockey.command(state,p,'start_solo'))
            assert(Hockey.command(state,p,'leave'))
            check('journey_hockey_can_restart_and_exit_'..bay,Hockey.matches[bay]==nil)
        end
    end,debug.traceback)
    Hockey.matches=previous
    if not ok then error(reason,0) end
end

function Test.run(_,check)
    groceryRoutes(check)
    shoppingRecovery(check)
    hockeyJourney(check)
end
return Test
