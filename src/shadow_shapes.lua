-- Cheap, camera-independent casting proxies. No textures or GPU state here.
local S={}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
function S.sun(direction,height,maxLength)
    local y=direction[2]
    if y<=0 then return 0,0,0 end
    local x,z=-direction[1]*height/math.max(.12,y),-direction[3]*height/math.max(.12,y)
    local length=math.sqrt(x*x+z*z);local scale=math.min(1,(maxLength or 18)/math.max(.001,length))
    return x*scale,z*scale,clamp(y/.15,0,1)
end
function S.point(x,y,h,lx,ly,lh)
    local f=math.min(.65,h/math.max(1,lh-h))
    return x+(x-lx)*f,y+(y-ly)*f
end
function S.hull(points)
    table.sort(points,function(a,b)return a[1]==b[1] and a[2]<b[2] or a[1]<b[1] end)
    local unique={};for _,p in ipairs(points)do local q=unique[#unique];if not q or p[1]~=q[1] or p[2]~=q[2] then unique[#unique+1]=p end end
    if #unique<3 then return {} end
    local function cross(a,b,c)return (b[1]-a[1])*(c[2]-a[2])-(b[2]-a[2])*(c[1]-a[1])end
    local out={};for _,p in ipairs(unique)do while #out>=2 and cross(out[#out-1],out[#out],p)<=0 do table.remove(out)end;out[#out+1]=p end
    local lower=#out
    for i=#unique-1,1,-1 do local p=unique[i];while #out>lower and cross(out[#out-1],out[#out],p)<=0 do table.remove(out)end;out[#out+1]=p end
    table.remove(out);local flat={};for _,p in ipairs(out)do flat[#flat+1]=p[1];flat[#flat+1]=p[2]end;return flat
end
-- A vertical silhouette: normalized width and height, including ears / limbs.
S.person={{-.25,0},{-.30,.4},{-.52,.49},{-.43,.65},{-.24,.64},{-.28,.79},{-.35,1},{-.12,.92},{.12,.92},{.35,1},{.28,.79},{.24,.64},{.43,.65},{.52,.49},{.30,.4},{.25,0},{.08,0},{0,.31},{-.08,0}}
S.tree={{-.09,0},{-.09,.30},{-.5,.38},{-.62,.56},{-.43,.68},{-.47,.82},{-.18,.94},{0,1},{.27,.92},{.48,.78},{.4,.64},{.62,.5},{.43,.35},{.09,.30},{.09,0}}
S.pine={{-.08,0},{-.08,.2},{-.52,.2},{-.28,.44},{-.42,.44},{-.18,.67},{-.29,.67},{0,1},{.29,.67},{.18,.67},{.42,.44},{.28,.44},{.52,.2},{.08,.2},{.08,0}}
function S.silhouette(outline,x,z,width,dx,dz)
    local length=math.sqrt(dx*dx+dz*dz)
    local sx,sz=1,0;if length>.001 then sx,sz=-dz/length,dx/length end
    -- A small footprint component prevents collapse under an overhead light.
    local result={};for _,p in ipairs(outline)do
        result[#result+1]=x+sx*p[1]*width+dx*p[2]
        result[#result+1]=z+sz*p[1]*width+dz*p[2]+(p[2]-.5)*width*.18
    end;return result
end
function S.box(x,z,halfX,halfZ,dx,dz,heading)
    local c,s=math.cos(heading or 0),math.sin(heading or 0);local points={}
    for _,a in ipairs({-halfX,halfX})do for _,b in ipairs({-halfZ,halfZ})do
        local px,pz=x+a*c-b*s,z+a*s+b*c
        points[#points+1]={px,pz};points[#points+1]={px+dx,pz+dz}
    end end;return S.hull(points)
end
return S
