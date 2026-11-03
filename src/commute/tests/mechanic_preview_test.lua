-- Preview rotation must select the same logical direction for the image quad
-- and paint region. No renderer or asset allocation is needed for this contract.
local Interior=require('src.commute.mechanic_interior')
local PaintArt=require('src.commute.bike_paint_art')
local State=require('src.state')
local Test={}
function Test.run(check)
    local oldDraw,oldColor=PaintArt.draw,love.graphics.setColor
    local calls={}
    PaintArt.draw=function(image,quad,paint,x,y,rotation,sx,sy,ax,ay,frame,pose)
        calls[#calls+1]={quad=quad,paint=paint,frame=frame,pose=pose}
    end
    love.graphics.setColor=function()end
    local okay,reason=xpcall(function()
        local state=State.new();state.home.residents.owner.ridingPaintId='blue'
        local R={state=state,World={player={id=1,homeResidentId='owner'}}}
        local view={ready=true,bikeImage={},bikeFrameCount=16,bikeFrame=5,bikeQuads={}}
        for frame=1,16 do view.bikeQuads[frame]={id=frame} end
        local matched=true
        for frame=1,16 do
            assert(Interior.drawBike(view,R,0,0,1,'red',frame))
            local call=calls[#calls]
            matched=matched and call.quad==view.bikeQuads[frame] and call.frame==frame
                and call.paint=='red' and call.pose=='parked'
        end
        check('mechanic_preview_all_sixteen_physical_quads_match_paint_regions',matched and #calls==16)
        assert(Interior.drawBike(view,R,0,0,1))
        local last=calls[#calls]
        check('mechanic_preview_default_east_view_uses_owned_finish',last.quad==view.bikeQuads[5]
            and last.frame==5 and last.paint=='blue')
        local count=#calls;view.closed=true
        check('mechanic_preview_closed_room_does_not_draw',not Interior.drawBike(view,R,0,0,1,'red',16) and #calls==count)
    end,debug.traceback)
    PaintArt.draw,love.graphics.setColor=oldDraw,oldColor
    if not okay then error(reason,0)end
end
return Test
