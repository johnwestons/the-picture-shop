local Service=require('src.commute.bike_service')
local M=require('src.commute.vendor.mathx')
local Gauge={}
Gauge.beamLabels={off='LIGHT OFF',low='LOW BEAM',high='HIGH BEAM'}

function Gauge.read(bike)
    local fuel=M.clamp(bike.service and bike.service.fuel or Service.tank,0,Service.tank)
    local beam=bike.headlight and (bike.headlightHighBeam and 'high' or 'low') or 'off'
    return fuel,fuel/Service.tank,fuel<=Service.tank/8,beam
end

function Gauge.draw(t,reg,font)
    local g=love.graphics
    local x,y,r=reg.fuelX,reg.fuelY,reg.fuelR
    local pivotY=y+r*.14
    g.setLineWidth(1);g.setFont(font)
    for i=0,4 do
        local a=math.rad(205+32.5*i)
        if i==0 then g.setColor(.99,.63,.26) else g.setColor(.88,.88,.73) end
        g.line(x+r*.72*math.cos(a),pivotY+r*.72*math.sin(a),x+r*.90*math.cos(a),pivotY+r*.90*math.sin(a))
    end
    g.setColor(.90,.88,.74)
    g.print('E',x-r*.87,y+1,0,.8,.8);g.print('F',x+r*.65,y+1,0,.8,.8)
    g.printf('FUEL',x-r,y+r*.32,2*r,'center')
    local a=math.rad(205+130*t.fuelFraction)
    g.setColor(1,.54,.23);g.setLineWidth(1.8)
    g.line(x,pivotY,x+r*.82*math.cos(a),pivotY+r*.82*math.sin(a));g.circle('fill',x,pivotY,2)

    -- The lamp and pump share the dial's registration on both cockpit sprites.
    g.push();g.translate(x,y+r*1.62)
    g.setColor(.065,.08,.075,.98);g.rectangle('fill',-20,-6.5,40,13,3)
    g.setColor(.45,.44,.33);g.setLineWidth(1);g.rectangle('line',-20,-6.5,40,13,3)
    if t.beam=='high' then g.setColor(.49,.80,1)
    elseif t.beam=='low' then g.setColor(.67,.95,.51)
    else g.setColor(.31,.35,.31) end
    g.setLineWidth(1.5);g.line(-9,-3.5,-6,-3,-4,0,-6,3,-9,3.5,-9,-3.5)
    for row=-1,1 do g.line(-11,row*2.4,-16,row*2.4+(t.beam=='low' and 1.6 or 0)) end
    if t.lowFuel then g.setColor(1,.63,.16) else g.setColor(.31,.35,.31) end
    g.rectangle('line',5,-4,6,8,1);g.line(6,-1,10,-1);g.line(11,0,13,0,13,3,15,3,15,-1,13,-3)
    g.pop()
end
return Gauge
