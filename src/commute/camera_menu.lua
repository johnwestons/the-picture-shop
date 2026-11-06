local Menu={}
Menu.modes={{'fixed','Free camera'},{'follow','Follow rider'},{'shoulder','Over the shoulder'},
    {'first','First person'},{'center','Recenter view'}}

function Menu.row(button,i)
    return {x=button.x+button.width-175,y=button.y+button.height+4+(i-1)*38,width=175,height=37}
end
function Menu.hasTruckSeatPad(camera,rider)
    return camera and camera.firstPerson and rider and rider.vehicle=='truck'
end
function Menu.seatPad(button)
    local last=Menu.row(button,#Menu.modes)
    local frame={x=last.x,y=last.y+last.height+5,width=last.width,height=98}
    local center=frame.x+frame.width*.5
    local size=36
    return frame,{
        up={x=center-size*.5,y=frame.y+22,width=size,height=22},
        left={x=frame.x+30,y=frame.y+46,width=size,height=22},
        right={x=frame.x+frame.width-30-size,y=frame.y+46,width=size,height=22},
        down={x=center-size*.5,y=frame.y+70,width=size,height=22},
    }
end
function Menu.adjustmentAt(button,x,y,camera,rider)
    if not Menu.hasTruckSeatPad(camera,rider) then return nil end
    local _,buttons=Menu.seatPad(button)
    for direction,rect in pairs(buttons) do
        if x>=rect.x and x<=rect.x+rect.width and y>=rect.y and y<=rect.y+rect.height then
            return direction
        end
    end
end
function Menu.enabled(id,rider)
    local mounted=rider and (rider.gear.mounted or rider.vehicle=='truck')
    if id=='first' then return rider and not rider.gear.transition end
    return id~='shoulder' or mounted and not rider.gear.transition
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
    if Menu.hasTruckSeatPad(camera,rider) then
        local frame,buttons=Menu.seatPad(button)
        g.setColor(.06,.10,.09,.97);g.rectangle('fill',frame.x,frame.y,frame.width,frame.height,4)
        g.setColor(.72,.79,.72,1);g.printf('CAB SEAT POSITION',frame.x+4,frame.y+4,frame.width-8,'center')
        for direction,rect in pairs(buttons) do
            g.setColor(.14,.21,.17,1);g.rectangle('fill',rect.x,rect.y,rect.width,rect.height,4)
            g.setColor(.92,.91,.80,1)
            local cx,cy=rect.x+rect.width*.5,rect.y+rect.height*.5
            if direction=='up' then g.polygon('fill',cx,cy-6,cx-6,cy+4,cx+6,cy+4)
            elseif direction=='down' then g.polygon('fill',cx,cy+6,cx-6,cy-4,cx+6,cy-4)
            elseif direction=='left' then g.polygon('fill',cx-7,cy,cx+4,cy-6,cx+4,cy+6)
            else g.polygon('fill',cx+7,cy,cx-4,cy-6,cx-4,cy+6) end
        end
    end
    g.pop()
end
return Menu
