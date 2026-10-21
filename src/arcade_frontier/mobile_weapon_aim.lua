local Manifest=require("src.arcade_frontier.first_person_weapon_manifest")
local Grips=require("src.arcade_frontier.first_person_weapon_grips")
local Muzzles=require("src.arcade_frontier.first_person_weapon_muzzles")
local WeaponActions=require("src.arcade_frontier.first_person_weapon_actions")
local Aim={}

local function gripFor(weapon,view)
    local views=Grips[weapon] or {}
    return views[view] or views.hip or {x=.5,y=.7,aspect=1}
end

-- Both shooting games use the same phone-sized weapon and grip-to-reticle
-- geometry. ADS preserves the calibrated sight; hip fire keeps a clear aiming
-- point above the hand. Coordinates are logical canvas pixels, before scaling.
function Aim.geometry(weapon,mode,width,height)
    width,height=width or 960,height or 720
    mode=mode=="sights" and "sights" or "hip"
    local actionAnchors=WeaponActions.anchorsFor(weapon)
    local grip=(mode=="hip" and actionAnchors and actionAnchors.grip) or gripFor(weapon,mode)
    local gap=height*.20
    local artHeight=math.min(height*.50,width*.56/grip.aspect)
    local offsetX,offsetY=0,gap
    local sight,calibrated=Manifest.anchorFor(weapon)
    if mode=="sights" and calibrated and grip.y>sight.y then
        artHeight=math.min(gap/(grip.y-sight.y),height*.66,width*.65/grip.aspect)
        offsetX=(grip.x-sight.x)*artHeight*grip.aspect
        offsetY=(grip.y-sight.y)*artHeight
    elseif mode=="hip" and (actionAnchors and actionAnchors.muzzle or Muzzles[weapon]) then
        local muzzle=actionAnchors and actionAnchors.muzzle or Muzzles[weapon]
        local bore=actionAnchors and actionAnchors.bore or grip
        local dx=(muzzle.x-bore.x)*grip.aspect
        local dy=muzzle.y-bore.y
        local gripDx=(muzzle.x-grip.x)*grip.aspect
        local gripDy=muzzle.y-grip.y
        local length=math.sqrt(dx*dx+dy*dy)
        if length>.001 then
            local extension=math.min(height*.09,artHeight*.18)
            offsetX=-gripDx*artHeight-extension*dx/length
            offsetY=-gripDy*artHeight-extension*dy/length
        end
    end
    return {height=artHeight,offsetX=offsetX,offsetY=offsetY,gripAnchor=grip}
end

function Aim.gripForAim(weapon,mode,x,y,width,height)
    local geometry=Aim.geometry(weapon,mode,width,height)
    return x+geometry.offsetX,y+geometry.offsetY
end

function Aim.set(state,x,y,weapon,mode,width,height,bounds)
    width,height=width or 960,height or 720
    bounds=bounds or {left=0,top=0,right=width,bottom=height}
    state.touchAim={x=x,y=y,width=width,height=height,bounds=bounds}
    local geometry=Aim.geometry(weapon,mode,width,height)
    state.aimX=math.max(bounds.left,math.min(bounds.right,x-geometry.offsetX))
    state.aimY=math.max(bounds.top,math.min(bounds.bottom,y-geometry.offsetY))
end

function Aim.refresh(state,weapon,mode)
    local touch=state.touchAim
    if touch then Aim.set(state,touch.x,touch.y,weapon,mode,touch.width,touch.height,touch.bounds) end
end

function Aim.placement(weapon,view,mode,x,y,width,height)
    local geometry=Aim.geometry(weapon,mode,width,height)
    local actionAnchors=WeaponActions.anchorsFor(weapon)
    local grip=(view=="hip" and actionAnchors and actionAnchors.grip) or gripFor(weapon,view)
    local artWidth=geometry.height*grip.aspect
    local handX,handY=x+geometry.offsetX,y+geometry.offsetY
    return {x=handX-grip.x*artWidth,y=handY-grip.y*geometry.height,
        width=artWidth,height=geometry.height,gripX=handX,gripY=handY,gripAnchor=grip}
end

-- Fire frames may briefly replace an ADS weapon view. Scale that authored
-- sprite to the sight view and pin its measured muzzle just behind the reticle.
function Aim.actionMuzzlePlacement(weapon,x,y,width,height)
    width,height=width or 960,height or 720
    local anchors=WeaponActions.anchorsFor(weapon)
    local grip=anchors and anchors.grip or gripFor(weapon,"hip")
    local muzzle=anchors and anchors.muzzle or Muzzles[weapon]
    if not muzzle then return nil end
    local bore=anchors and anchors.bore or grip
    local dx=(muzzle.x-bore.x)*grip.aspect
    local dy=muzzle.y-bore.y
    local length=math.sqrt(dx*dx+dy*dy)
    if length<.001 then return nil end
    local artHeight=math.min(height*.94,width*1.03)
    local extension=math.min(height*.045,artHeight*.07)
    local muzzleX=x-dx/length*extension
    local muzzleY=y-dy/length*extension
    local artWidth=artHeight*grip.aspect
    return {x=muzzleX-muzzle.x*artWidth,y=muzzleY-muzzle.y*artHeight,
        width=artWidth,height=artHeight,muzzleX=muzzleX,muzzleY=muzzleY,
        muzzleAnchor=muzzle,gripAnchor=grip}
end

-- ADS action frames are portrait sprite cells with their own calibrated
-- sight anchor. They replace the aimed view in place, so the sight picture
-- does not jump over to the hip-fire pose while the player shoots.
function Aim.adsActionPlacement(weapon,x,y,width,height,frameWidth,frameHeight,maxWidth,maxHeight,frame)
    width,height=width or 960,height or 720
    frameWidth,frameHeight=tonumber(frameWidth) or 0,tonumber(frameHeight) or 0
    if frameWidth<=0 or frameHeight<=0 then return nil end
    maxWidth=maxWidth or width*1.03
    maxHeight=maxHeight or height*.94
    local anchor=Manifest.adsActionAnchorFor(weapon,frame)
    local scale=math.min(maxWidth/frameWidth,maxHeight/frameHeight)
    return {x=x-anchor.x*frameWidth*scale,y=y-anchor.y*frameHeight*scale,
        width=frameWidth*scale,height=frameHeight*scale,scale=scale,anchor=anchor}
end

return Aim
