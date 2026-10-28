-- Each atlas cell is the same authored layer at a different vertical position.
-- Source travel is measured in the 768x512 atlas cell, before scene scaling.
local Motion = {}
local function fraction(value)
    return math.max(0,math.min(1,tonumber(value) or 0))
end

function Motion.frame(progress)
    return math.floor(fraction(progress)*4+.5)+1
end

function Motion.sample(name,progress)
    local phase=fraction(progress)
    if name=="cutterBlade" then
        return 1,88*2*math.min(phase,1-phase)
    elseif name=="cutterClamp" then
        return 1,58*phase
    end
    return Motion.frame(phase),0
end

return Motion
