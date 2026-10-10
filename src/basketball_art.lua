local Animation=require("src.character_animation")
local Path=require("src.basketball_trajectory")
local Config=require("src.config")
local Art={CELL=256,ANCHOR_X=128,ANCHOR_Y=240,HEIGHT=196}
Art.mirrors={west="east",northwest="northeast",southwest="southeast"}
-- Separate ball centers, measured against the normalized palms. First eight
-- dribble poses, then twelve gather/rise/apex poses.
Art.hands={
    north={{183,163},{185,201},{187,222},{188,157},{183,169},{185,190},{186,219},{179,169},
        {129,154},{129,156},{131,152},{155,126},{157,99},{160,76},{166,65},{164,56},
        {157,88},{164,86},{164,74},{168,66}},
    northeast={{185,177},{198,201},{197,227},{195,168},{187,183},{204,195},{201,224},{202,179},
        {162,150},{165,144},{175,131},{178,125},{175,114},{180,99},{180,78},{190,61},
        {186,96},{190,83},{187,64},{181,49}},
    east={{186,171},{187,201},{195,228},{194,165},{192,178},{193,200},{192,222},{200,178},
        {180,156},{181,169},{187,124},{185,123},{179,130},{182,111},{190,101},{190,64},
        {184,92},{176,82},{189,72},{191,65}},
    southeast={{184,174},{187,201},{187,228},{190,171},{194,180},{200,200},{196,222},{200,180},
        {178,166},{186,168},{184,147},{187,142},{178,136},{177,116},{180,107},{185,81},
        {174,91},{172,87},{172,84},{183,96}},
    south={{91,173},{88,205},{101,229},{96,171},{95,180},{103,213},{96,185},{100,214},
        {127,171},{128,174},{126,151},{127,138},{126,137},{128,126},{125,92},{127,71},
        {122,91},{128,90},{126,74},{127,70}},
}
function Art.direction(player)
    local x,y=tonumber(player.intentX) or 0,tonumber(player.intentY) or 0
    if math.abs(x)+math.abs(y)<.001 then x,y=tonumber(player.velocityX) or player.facing or 1,tonumber(player.velocityY) or 0 end
    return Animation.authoredDirection(x,y)
end
function Art.scale() return Config.characterRendering.referenceHeight*Config.player.drawScale/Art.HEIGHT end
function Art.chargeFrame(elapsed) return math.min(12,math.floor(math.max(0,elapsed)/Path.APEX*12)+1) end
function Art.ballPoint(player,frame,jump)
    local direction=Art.direction(player)
    local authored=Art.mirrors[direction] or direction
    local hand=Art.hands[authored][frame]
    if not hand then return end
    local scale=Art.scale()
    local y=player.y+(hand[2]-Art.ANCHOR_Y)*scale-(jump or 0)
    if frame<=8 then y=math.min(y,player.y-Path.RADIUS) end
    return player.x+(hand[1]-Art.ANCHOR_X)*scale*(Art.mirrors[direction] and -1 or 1),y
end
function Art.releasePoint(player,elapsed)
    return Art.ballPoint(player,8+Art.chargeFrame(elapsed),Path.jumpHeight(elapsed))
end
return Art
