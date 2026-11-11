-- Device-local presentation policy; never part of simulation or multiplayer state.
local Video={}
local function distance(v,fallback)return (v=='near' or v=='medium' or v=='far')and v or fallback end
function Video.normalize(v)
    v=type(v)=='table' and v or {}
    return {dynamicShadows=v.dynamicShadows~=false,vegetationShadows=v.vegetationShadows==true,
        shadowDistance=distance(v.shadowDistance,'medium'),renderDistance=distance(v.renderDistance,'medium')}
end
Video.current=Video.normalize()
function Video.apply(v)Video.current=Video.normalize(v);return Video.current end
function Video.renderRadius()return ({near=48,medium=72,far=96})[Video.current.renderDistance]end
function Video.shadowRadius()return ({near=18,medium=28,far=36})[Video.current.shadowDistance]end
return Video
