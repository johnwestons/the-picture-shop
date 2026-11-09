-- Starting resources for live acceptance, not completion evidence. Actions after
-- this setup still use real App controls, authoritative commands and transport.
assert(R.multiplayer:isHost() or not R.multiplayer:isActive())
local Calendar=require('src.business_calendar')
R.state.calendar=Calendar.dateFromHours(9)
R.state.calendar.secondsPerDay=3600;R.state.calendar.elapsed=9/24*3600
R.state.money=250000
R.state.employment.recruiting=false
R.state.home=require('src.home').new({town=assert(require('src.commute.town').generate(712345)),
    apartmentId='garden',furnishingPreset='modest'},R.state.calendar.totalDays)
R.state.home.balanceCents=500000
for _,id in ipairs({'bread','vegetables','bottled_drink','rough_sandwich'}) do R.state.home.inventory[id]=8 end
assert(require('src.home').valid(R.state.home),'Invalid starting household')
local Editor=require('src.save_editor')
for _,field in ipairs(Editor.fields('supplies')) do assert(Editor.setValue(R.state,field.id,30)) end
local context={state=R.state,save=R.Save,useActiveState=true,saveCurrent=function()return R.saveCurrent(true)end}
for _,id in ipairs({'heidelberg_10x15','front_left:air_hockey','front_right:critter_kombat','forklift'}) do
    assert(Editor.grantSlot(context,R.state.activeSlot,id))
end
R.World.load();R.World.update(0,0,0,R.Assets,R.state)
R.state.screen='world'
assert(R.saveCurrent(true))
R.multiplayer:markShopDirty()
return {state=R.liveInspect(),machines=R.state.machines.items,home=R.state.home.apartmentId}
