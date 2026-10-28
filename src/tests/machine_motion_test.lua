local State=require("src.state")
local Machine=require("src.machine")
local Render=require("src.screens.machine.render")
local Presentation=require("src.screens.cutter_presentation")
local Motion=require("src.screens.cutter_motion")
local Test={}

function Test.run(_,check)
    local startCell,startOffset=Motion.sample("cutterBlade",.3)
    local midCell,midOffset=Motion.sample("cutterBlade",.15)
    local returningCell,returningOffset=Motion.sample("cutterBlade",.7)
    check("cutter_blade_return_moves_between_former_identical_atlas_selections",
        startCell==midCell and startCell==1 and midOffset>0 and midOffset<startOffset)
    check("cutter_same_physical_depth_uses_same_authored_layer_on_both_stroke_halves",
        returningCell==startCell and math.abs(returningOffset-startOffset)<.00001)
    local downCell,downOffset=Motion.sample("cutterBlade",.5)
    local homeCell,homeOffset=Motion.sample("cutterBlade",1)
    check("cutter_authored_blade_reaches_full_depth_and_returns_home",
        downCell==1 and homeCell==1 and downOffset==88 and homeOffset==0)
    local firstClamp,firstClampOffset=Motion.sample("cutterClamp",.4)
    local nextClamp,nextClampOffset=Motion.sample("cutterClamp",.41)
    check("cutter_clamp_moves_within_a_former_single_atlas_step",
        firstClamp==1 and nextClamp==1 and nextClampOffset>firstClampOffset)
    local state=State.new()
    local machine=Machine.forId("MCH-ANIMATION-MOTION")
    local runtime={Screen={},drawPaper=function()end}
    Render.install(runtime)
    local motions={}
    runtime.drawMotion=function(_,name,_,progress)motions[name]=progress end
    local assets={get=function()return nil end}
    for _,stop in ipairs({"emergency","barrier"}) do
      for _,cyclePhase in ipairs({.3,.7}) do
        local case=stop..(cyclePhase>.5 and "_returning" or "")
        machine.reset(state)
        machine.paper=require("src.paper_work").createStockPaper()
        machine.legacyPaper,machine.loaded=true,true
        machine.step="cutting"
        machine.update(machine.cycleTime*cyclePhase,state)
        local depth=machine.bladeProgress
        motions={};runtime.drawMachine(assets,machine)
        -- Atlas poses 1/5 and 2/4 are identical. The same physical blade
        -- depth can therefore use either half of the cycle after stopping.
        local before=math.min(motions.cutterBlade,1-motions.cutterBlade)
        if stop=="emergency" then machine.emergencyStop(state)
        else machine.setBarrier(false,state) end
        machine.update(.1,state)
        motions={};runtime.drawMachine(assets,machine)
        check("cutter_"..case.."_keeps_blade_visible_at_stopped_depth",
            machine.step=="blocked" and depth>0 and machine.bladeProgress==depth
            and math.abs(motions.cutterBlade-before)<.00001)
        local view=machine.networkView(state,false)
        local guest=Presentation.new();guest:accept(view)
        local model=guest:model(state,view)
        motions={};runtime.drawMachine(assets,model)
        check("cutter_"..case.."_guest_keeps_the_same_stopped_blade",
            math.abs(model.bladeProgress-depth)<.001 and math.abs(motions.cutterBlade-before)<.001)
        machine.resetSafety(state)
        check("cutter_"..case.."_reset_starts_from_existing_blade_position",machine.bladeProgress==depth)
        machine.update(.1,state)
        motions={};runtime.drawMachine(assets,machine)
        check("cutter_"..case.."_reset_returns_blade_without_teleport",
            machine.step=="resetting" and machine.bladeProgress>0 and machine.bladeProgress<depth
            and motions.cutterBlade>0 and motions.cutterBlade<before)
        machine.update(.3,state)
        check("cutter_"..case.."_reset_finishes_with_blade_home",
            machine.bladeProgress==0 and machine.step=="loaded" and machine.loaded)
      end
    end
    machine.reset(state)
end

return Test
