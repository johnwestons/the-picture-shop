local Test={}
function Test.run(check)
    local Registration=require("src.home_mop_registration")
    local Art=require("src.home_mop_art")
    local expected={"east","southeast","south","southwest","west","northwest","north","northeast"}
    local directions=Registration.order
    local matches=Registration.fps==6 and Registration.duration==1 and #Registration.sequence==6
    for index,direction in ipairs(expected) do matches=matches and directions[index]==direction end
    check("home_mop_registers_all_eight_sweep_directions_and_cadence",matches
        and love.filesystem.getInfo(Registration.prop)~=nil)
    local contacts=true
    for _,direction in ipairs(directions) do
        for frame=1,4 do contacts=contacts and Art.contact(direction,frame).valid end
    end
    check("home_mop_matches_all_32_registered_sweep_grips",contacts)
    local player={character="rabbit-worker",furColorway=1,overallsColorway=1}
    local drawn=true
    local canvas=love.graphics.newCanvas(960,480)
    love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(.13,.16,.18,1)
    for index,direction in ipairs(directions) do
        love.graphics.push();love.graphics.translate(115+(index-1)%4*240,200+math.floor((index-1)/4)*240)
        love.graphics.scale(1.6)
        local result=Art.draw(direction,3,0,0,player)
        drawn=drawn and result~=false
        love.graphics.pop()
    end
    love.graphics.pop();canvas:release();Art.release()
    check("home_mop_directional_props_and_sweep_bodies_draw",drawn)
end
return Test
