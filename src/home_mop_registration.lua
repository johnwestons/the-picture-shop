-- Story warehouse mopping shares the apartment sweep body's eight views,
-- phase order, grip points and tool contacts; only the directional prop differs.
local Sweep=require("src.home_sweep_registration")
return {order=Sweep.order,sequence=Sweep.sequence,fps=Sweep.fps,
    duration=#Sweep.sequence/Sweep.fps,views=Sweep.views,
    contacts=Sweep.mops,prop="assets/generated/home-routines-v2/mop-eight-directions-v1.png"}
