"""Physical regression for grocery unload acknowledgments and home routines."""
import json,time
import run_live_shared_activities as S
N=S.N
N.OUT=N.ROOT/'output/live-gameplay-20261109/home-retest';N.OUT.mkdir(exist_ok=True);N.checks=[]
pc,phone,check,wait=N.pc,N.phone,N.check,N.wait
N.helpers()
check('host_restart_automatically_rejoined',phone('return R.multiplayer.ready and #R.state.jobs.completed==1'))
pc("local p=R.multiplayer.players[2];p.sceneId='home';local r=require('src.home_residents').get(R.state,p);r.sceneId='home';r.bikeParkedAtHome=true;r.bikeInventory.items={bread=1,vegetables=1};r.bikeInventory.revision=r.bikeInventory.revision+1;R.multiplayer:markShopDirty(true);return true")
point=pc("return require('src.home_bike_cargo').target(R.multiplayer.players[2],R.state)");S.scene('home',point['x'],point['y'])
rev=pc("return require('src.home_residents').get(R.state,R.multiplayer.players[2]).bikeInventory.revision")
before=pc('return R.state.home.inventory.bread')
servings=pc("return require('src.home_shop_catalog').PRODUCTS.bread.servings")
S.interact('unload_acknowledged','homeActivity','bike:all:'+str(rev))
check('unload_added_once',pc('return R.state.home.inventory.bread=='+str(before+servings)))
S.interact('stale_unload_gets_rejection','homeActivity','bike:all:'+str(rev),False)
check('stale_unload_cannot_duplicate_food',phone('return R.state.home.inventory.bread=='+str(before+servings)))
point=pc("local L=require('src.home_layouts');local x,y=L.toWorld(unpack(L.get(R.state).fixtures.sink.approach));return {x=x,y=y}");S.scene('home',point['x'],point['y'])
S.interact('drink_at_sink','homeActivity','drink:sink')
wait(lambda:pc("return require('src.home_residents').get(R.state,R.multiplayer.players[2]).activity==nil"),seconds=30)
check('drink_finishes',True)
S.interact('start_washing','homeActivity','wash:sink')
S.interact('cancel_washing','homeActivity','cancel')
check('cancel_releases_sink',pc("return require('src.home_residents').get(R.state,R.multiplayer.players[2]).activity==nil"))
S.interact('start_cooking','homeActivity','prepare:sink')
S.interact('cancel_cooking','homeActivity','cancel')
S.interact('start_floor_sleep','homeActivity','sleepfloor:floor')
S.interact('wake_from_sleep','homeActivity','cancel')
check('guest_home_does_not_move_host',pc("return R.World.player.sceneId=='warehouse'"))
check('valid_durable_home',pc('local s,e=R.SaveSchema.snapshot(R.state);assert(s,e);assert(R.saveCurrent(true));return true'))
S.snap('home-routines-completed')
