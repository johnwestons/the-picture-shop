-- The warehouse mop reuses the apartment's reviewed eight-way sweep bodies,
-- hand contacts, cadence and planted-foot registration with its own prop atlas.
local Sweep=require("src.home_sweep_art")
local Registration=require("src.home_mop_registration")
local Art={order=Registration.order,sequence=Registration.sequence,fps=Registration.fps,
    duration=#Registration.sequence/Registration.fps}
function Art.frame(seconds)return Sweep.frame(seconds) end
function Art.contact(direction,frame)return Sweep.contact(direction,frame,"mop") end
function Art.prewarm(direction)return Sweep.prewarmMop(direction) end
function Art.draw(direction,frame,x,y,player)return Sweep.drawMop(direction,frame,x,y,player) end
function Art.release()return Sweep.release() end
return Art
