local M=require('src.commute.vendor.mathx')
local Stream={}
local extraChances={.010,.030,.045}
local extraChances2={.026,.012,.030,.050,.032}
local extraChances3={.035,.032,.028,.026,.028,.030,.026,.030}
local extraChances4={.018,.007,.015,.012}
local function radius(kind,scale)
    if kind=='rock' then return .90*scale end
    if kind=='log' then return .55*scale end
    return (kind=='oak' or kind=='pine' or kind=='redbud' or kind=='dogwood' or kind=='persimmon') and .24*scale or 0
end
function Stream:candidate(ix,iz,slot)
    if ix<0 or iz<0 or ix>=self.propWidth or iz>=self.propWidth then return nil end
    local id=(iz*self.propWidth+ix)*2+slot+3
    local x=ix*4+.4+M.hash(self.seed+11,id,slot)*3.2
    local z=iz*4+.4+M.hash(self.seed+29,id,slot)*3.2
    if M.length(x-self.spawn.x,z-self.spawn.z)<6 then return nil end
    local h=self.plan:height(x,z);if h<.4 then return nil end
    local n=M.hash(self.seed+71,id,slot)
    local canopy,conifer,rockiness=self.plan:habitat(x,z)
    local kind
    local elevation=M.smooth((h-5)/25)
    -- Terrain supplies the mountain faces. Sparse, low-frequency outcrop bands
    -- leave some mountain systems bare while keeping occasional alpine accents.
    local outcrop=M.smooth((M.noise(self.seed+601,x*.010,z*.010)-.42)/.34)
    local rockChance=.004+rockiness*.016*outcrop+elevation*.006*outcrop
    if n<rockChance then kind='rock'
    elseif n<rockChance+.04 then kind='log'
    elseif n<rockChance+.04+canopy*.43 then kind=conifer>.55 and 'pine' or 'oak'
    elseif n<.64 then kind='grass'
    elseif n<.79 then kind='strawberry'
    elseif n<.90 then kind='sumac' else kind='bramble' end
    local sizeRoll=M.hash(self.seed+97,id,slot)
    local scale
    if kind=='rock' then scale=.88+sizeRoll*.72+rockiness*1.15+elevation*.75
    elseif kind=='oak' or kind=='pine' then scale=.58+sizeRoll*1.18
    else scale=.75+sizeRoll*.55 end
    return {id=id,kind=kind,x=x,z=z,scale=scale,radius=radius(kind,scale),amount=1}
end
-- New flora use a separate append-only ID range so existing streamed-save
-- deltas continue to refer to exactly the same baseline plants.
function Stream:extraCandidate(ix,iz,slot)
    if ix<0 or iz<0 or ix>=self.propWidth or iz>=self.propWidth then return nil end
    local cell=iz*self.propWidth+ix;local cells=self.propWidth*self.propWidth
    local id=2*cells+4+cell*3+slot
    if M.hash(self.seed+211,id,slot)>=(extraChances[slot] or 0) then return nil end
    local x=ix*4+.4+M.hash(self.seed+181,id,slot)*3.2
    local z=iz*4+.4+M.hash(self.seed+197,id,slot)*3.2
    if M.length(x-self.spawn.x,z-self.spawn.z)<6 then return nil end
    local h=self.plan:height(x,z);if h<.4 then return nil end
    local canopy,moisture,rockiness=self.plan:habitat(x,z)
    local kind
    if slot==1 and canopy>.18 and moisture>.2 then kind='redbud'
    elseif slot==2 and canopy>.14 and canopy<.76 and moisture>.48 then kind='blueberry'
    elseif slot==3 and canopy<.62 and rockiness<.70 then kind='milkweed' end
    if not kind then return nil end
    local scale=kind=='redbud' and (.62+M.hash(self.seed+223,id,slot)*1.12)
        or (.78+M.hash(self.seed+223,id,slot)*.42)
    return {id=id,kind=kind,x=x,z=z,scale=scale,radius=radius(kind,scale),amount=1}
end
-- Newer plant additions live after the existing base and first expansion ID
-- ranges. Earlier saved IDs therefore keep their species and positions.
function Stream:extraCandidate2(ix,iz,slot)
    if ix<0 or iz<0 or ix>=self.propWidth or iz>=self.propWidth then return nil end
    local cell=iz*self.propWidth+ix;local cells=self.propWidth*self.propWidth
    local id=5*cells+8+cell*5+slot
    if M.hash(self.seed+313,id,slot)>=(extraChances2[slot] or 0) then return nil end
    local x=ix*4+.4+M.hash(self.seed+307,id,slot)*3.2
    local z=iz*4+.4+M.hash(self.seed+311,id,slot)*3.2
    if M.length(x-self.spawn.x,z-self.spawn.z)<6 then return nil end
    local h=self.plan:height(x,z);if h<.4 then return nil end
    local canopy,moisture,rockiness=self.plan:habitat(x,z)
    local community=self.plan:plantCommunity(x,z)
    local kind
    if slot==1 and (community=='woodland-understory' or community=='shrub-edge')
        and canopy>.30 and moisture>.30 and rockiness<.72 then kind='dogwood'
    elseif slot==2 and (community=='shrub-edge' or community=='sunny-opening')
        and canopy<.68 and moisture>.20 and rockiness<.58 then kind='persimmon'
    elseif slot==3 and community=='shrub-edge' and canopy<.70 and moisture>.22
        and moisture<.78 and rockiness<.68 then kind='chickasaw-plum'
    elseif slot==4 and community=='sunny-opening' and moisture<.76
        and rockiness<.60 then kind='little-bluestem'
    elseif slot==5 and (community=='woodland-understory' or community=='river-margin')
        and canopy>.28 and moisture>.40 and rockiness<.78 then kind='blue-phlox' end
    if not kind then return nil end
    local sizeRoll=M.hash(self.seed+317,id,slot)
    local scale=(kind=='dogwood' or kind=='persimmon') and (.58+sizeRoll*1.04)
        or kind=='little-bluestem' and (1.12+sizeRoll*.88)
        or kind=='chickasaw-plum' and (.78+sizeRoll*.44) or (.72+sizeRoll*.34)
    return {id=id,kind=kind,x=x,z=z,scale=scale,radius=radius(kind,scale),amount=1}
end
-- Seasonal wildflowers use a third append-only range. New flower IDs never
-- remap saved props from the base or the two earlier flora expansions.
function Stream:extraCandidate3(ix,iz,slot)
    if ix<0 or iz<0 or ix>=self.propWidth or iz>=self.propWidth then return nil end
    local cell=iz*self.propWidth+ix;local cells=self.propWidth*self.propWidth
    local id=10*cells+8+cell*8+slot
    if M.hash(self.seed+419,id,slot)>=(extraChances3[slot] or 0) then return nil end
    local x=ix*4+.4+M.hash(self.seed+401,id,slot)*3.2
    local z=iz*4+.4+M.hash(self.seed+409,id,slot)*3.2
    if M.length(x-self.spawn.x,z-self.spawn.z)<6 then return nil end
    local h=self.plan:height(x,z);if h<.4 then return nil end
    local canopy,moisture,rockiness=self.plan:habitat(x,z)
    local community=self.plan:plantCommunity(x,z)
    local kind
    if slot==1 and community=='woodland-understory' and canopy>.45 and moisture>.34
        and rockiness<.80 then kind='bloodroot'
    elseif slot==2 and community=='river-margin' and canopy>.20 and moisture>.46
        and rockiness<.82 then kind='virginia-bluebells'
    elseif slot==3 and (community=='woodland-understory' or community=='shrub-edge')
        and rockiness>.10 and canopy>.16 and moisture>.22 then kind='wild-columbine'
    elseif slot==4 and community=='sunny-opening' and moisture>.20
        and rockiness<.58 then kind='purple-coneflower'
    elseif slot==5 and (community=='sunny-opening' or community=='shrub-edge')
        and canopy<.60 and moisture>.24 and rockiness<.70 then kind='wild-bergamot'
    elseif slot==6 and community=='river-margin' and moisture>.62
        and rockiness<.82 then kind='cardinal-flower'
    elseif slot==7 and (community=='sunny-opening' or community=='shrub-edge')
        and canopy<.55 and moisture>.32 and rockiness<.75 then kind='new-england-aster'
    elseif slot==8 and community=='sunny-opening' and moisture<.76
        and rockiness<.72 then kind='common-goldenrod' end
    if not kind then return nil end
    local scale=.78+M.hash(self.seed+421,id,slot)*.48
    return {id=id,kind=kind,x=x,z=z,scale=scale,radius=0,amount=1}
end
-- Ground debris and small seasonal details use a fourth append-only ID range.
function Stream:extraCandidate4(ix,iz,slot)
    if ix<0 or iz<0 or ix>=self.propWidth or iz>=self.propWidth then return nil end
    local cell=iz*self.propWidth+ix;local cells=self.propWidth*self.propWidth
    local id=18*cells+20+cell*4+slot
    if M.hash(self.seed+521,id,slot)>=(extraChances4[slot] or 0) then return nil end
    local x=ix*4+.4+M.hash(self.seed+503,id,slot)*3.2
    local z=iz*4+.4+M.hash(self.seed+509,id,slot)*3.2
    if M.length(x-self.spawn.x,z-self.spawn.z)<6 then return nil end
    local h=self.plan:height(x,z);if h<.4 then return nil end
    local canopy,moisture,rockiness=self.plan:habitat(x,z)
    local community=self.plan:plantCommunity(x,z)
    local kind
    local woodland=community=='woodland-understory' or community=='shrub-edge'
        or community=='river-margin'
    if slot==1 and woodland and canopy>.20 and moisture>.22 then kind='twig'
    elseif slot==2 and woodland and canopy>.32 and moisture>.25 then kind='twig'
    elseif slot==3 and h>2 and (rockiness>.22 or h>8) then kind='stone'
    elseif slot==4 and (community=='woodland-understory' or community=='shrub-edge')
        and canopy>.43 and moisture>.28 then kind='leaf-litter' end
    if not kind then return nil end
    local sizeRoll=M.hash(self.seed+523,id,slot)
    local scale=kind=='stone' and (.72+sizeRoll*.78) or (.72+sizeRoll*.72)
    return {id=id,kind=kind,x=x,z=z,scale=scale,radius=0,amount=1}
end
return Stream
