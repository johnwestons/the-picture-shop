local M = {}
local bit=require('bit')
function M.clamp(n,a,b) return math.max(a,math.min(b,n)) end
function M.lerp(a,b,t) return a+(b-a)*t end
function M.smooth(n) n=M.clamp(n,0,1); return n*n*(3-2*n) end
function M.length(x,y) return math.sqrt(x*x+y*y) end
function M.finite(n) return type(n)=='number' and n==n and math.abs(n)<1e12 end
-- Extracted from Mouse Frontier's battle_field.lua (Park-Miller + value noise).
function M.random(seed)
    local state=math.floor(seed or 1)%2147483647; if state<=0 then state=1 end
    return function(a,b)
        state=(state*16807)%2147483647
        local n=(state-1)/2147483646
        if a==nil then return n end
        if b==nil then b=a;a=1 end
        return a+math.floor(n*(b-a+1))
    end
end
function M.hash(seed,x,z)
    -- Integer avalanche avoids long diagonal bands / similar neighbouring seeds.
    -- Intermediates are exact Lua integers before explicit 32-bit reduction.
    local n=bit.tobit(seed+x*374761393+z*668265263)
    n=bit.tobit(n+bit.lshift(n,10));n=bit.bxor(n,bit.rshift(n,6))
    n=bit.tobit(n+bit.lshift(n,3));n=bit.bxor(n,bit.rshift(n,11))
    n=bit.tobit(n+bit.lshift(n,15))
    return bit.band(n,2147483647)/2147483647
end
function M.noise(seed,x,z)
    local ix,iz=math.floor(x),math.floor(z)
    local u,v=M.smooth(x-ix),M.smooth(z-iz)
    return M.lerp(M.lerp(M.hash(seed,ix,iz),M.hash(seed,ix+1,iz),u),
        M.lerp(M.hash(seed,ix,iz+1),M.hash(seed,ix+1,iz+1),u),v)
end
return M
