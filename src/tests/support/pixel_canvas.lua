-- Fixed-coordinate pixel assertions use authored pixels on every platform.
-- Runtime/device viewport tests retain native DPI and normalize their readback.
return function(width,height,settings)
    local options={dpiscale=1}
    for key,value in pairs(settings or {}) do options[key]=value end
    return love.graphics.newCanvas(width,height,options)
end
