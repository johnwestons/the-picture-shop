local Controls=require('src.home_activity_controls')
local Menu={}
function Menu.choose(R,command)
    if R.state.screen~='home_activity' then return false end
    for _=1,20 do
        local visible,pages=Controls.visibleRows(R)
        for index,row in ipairs(visible) do
            if row.command==command then
                return Controls.keypressed(tostring(index),R)
            end
        end
        if Controls.page>=pages then break end
        Controls.keypressed('right',R)
    end
    return false
end
return Menu
