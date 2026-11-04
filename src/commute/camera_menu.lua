local Menu={}
Menu.modes={{'fixed','Free camera'},{'follow','Follow rider'},{'shoulder','Over the shoulder'},
    {'first','First person'},{'center','Recenter view'}}

function Menu.row(button,i)
    return {x=button.x+button.width-175,y=button.y+button.height+4+(i-1)*38,width=175,height=37}
end
function Menu.enabled(id,rider)
    return id~='first' and id~='shoulder' or rider.gear.mounted and not rider.gear.transition
end
function Menu.currentLabel(camera)
    local id=camera.firstPerson and 'first' or camera.outsideMode
    for _,mode in ipairs(Menu.modes) do if mode[1]==id then return mode[2] end end
    return Menu.modes[1][2]
end
function Menu.draw(button,camera,rider)
    local g=love.graphics
    local current=camera.firstPerson and 'first' or camera.outsideMode
    g.push('all')
    for i,mode in ipairs(Menu.modes) do
        local row=Menu.row(button,i)
        g.setColor(.06,.10,.09,.97);g.rectangle('fill',row.x,row.y,row.width,row.height,4)
        if Menu.enabled(mode[1],rider) then g.setColor(.90,.87,.71) else g.setColor(.45,.48,.45) end
        if mode[1]~='center' then
            g.circle('line',row.x+14,row.y+18,5)
            if mode[1]==current then g.circle('fill',row.x+14,row.y+18,3) end
        end
        g.print(mode[2],row.x+26,row.y+(row.height-g.getFont():getHeight())*.5)
    end
    g.pop()
end
return Menu
