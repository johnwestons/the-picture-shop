-- Ordered by continuous habitat axes so transitions never pass through an
-- unrelated material. IDs are zero-based atlas cells; source art is immutable.
local M=require('src.commute.vendor.mathx')
local P={COLUMNS=4,ROWS=4,groups={{base=0,count=4},{base=4,count=6},{base=10,count=6}},
    records={
        {name='dry-grass',color={.43,.43,.24}},
        {name='grass',color={.31,.40,.19}},
        {name='wild-grass',color={.28,.38,.18}},
        {name='moss',color={.24,.35,.19}},
        {name='shore-sand',color={.53,.49,.34}},
        {name='gravel',color={.45,.44,.36}},
        {name='dirt',color={.41,.33,.22}},
        {name='damp-soil',color={.30,.27,.20}},
        {name='shale-scree',color={.36,.35,.31}},
        {name='rock-outcrop',color={.31,.32,.30}},
        {name='pine-needles',color={.38,.31,.20}},
        {name='leaf-mulch',color={.32,.28,.19}},
        {name='leaves',color={.40,.32,.19}},
        {name='twig-litter',color={.34,.27,.19}},
        {name='bark-fragments',color={.31,.23,.16}},
        {name='autumn-leaves',color={.42,.29,.18}},
    }}
local function pair(group,value)
    local g=P.groups[group];value=M.clamp(value,0,g.count-1)
    local lo=math.floor(value)
    return g.base+lo+1,g.base+math.min(lo+1,g.count-1)+1,value-lo
end
function P.tint(gv,sv,lv,gw,sw,lw)
    local r,g,b=0,0,0
    local a,c,t=pair(1,gv);local ca,cb=P.records[a].color,P.records[c].color
    r=r+M.lerp(ca[1],cb[1],t)*gw;g=g+M.lerp(ca[2],cb[2],t)*gw;b=b+M.lerp(ca[3],cb[3],t)*gw
    a,c,t=pair(2,sv);ca,cb=P.records[a].color,P.records[c].color
    r=r+M.lerp(ca[1],cb[1],t)*sw;g=g+M.lerp(ca[2],cb[2],t)*sw;b=b+M.lerp(ca[3],cb[3],t)*sw
    a,c,t=pair(3,lv);ca,cb=P.records[a].color,P.records[c].color
    return r+M.lerp(ca[1],cb[1],t)*lw,g+M.lerp(ca[2],cb[2],t)*lw,b+M.lerp(ca[3],cb[3],t)*lw
end
-- Diagnostics/acceptance helper; the render hot path uses scalar attributes.
function P.weights(gv,sv,lv,gw,sw,lw,litterSeasonShift)
    local result={};for i=1,#P.records do result[i]=0 end
    local deciduousLitter=lv+(litterSeasonShift or 0)*M.clamp(lv*.5,0,1)
    for group,v in ipairs({{gv,gw},{sv,sw},{deciduousLitter,lw}}) do
        local a,b,t=pair(group,v[1]);result[a]=result[a]+v[2]*(1-t);result[b]=result[b]+v[2]*t
    end
    return result
end
return P
