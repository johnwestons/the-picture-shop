local Text = require('src.screens.typography')
local Fonts = {}

function Fonts.get(kind, size)
    return Text.get(size,kind=='paper' and 'regular' or 'bold')
end

function Fonts.fit(kind, text, size, width, height)
    return Text.fit(text,size,width,height,kind=='paper' and 'regular' or 'bold',12)
end

return Fonts
