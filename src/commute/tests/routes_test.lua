local Roads=require('src.commute.roads')
local Routes=require('src.commute.routes')
local Test={}
function Test.run(check)
    local roads=Roads.new();local routes=Routes.new(roads)
    for id in pairs(roads.destinations) do if id~='warehouse' then
        local out=routes:find('warehouse',id);local back=routes:find(id,'warehouse')
        check('commute_route_reachable_both_directions_'..id,out and back and out.length>0
            and math.abs(out.length-back.length)<.001,out and ('%.1f metres'):format(out.length))
        check('commute_route_bridge_only_for_east_bank_'..id,out and out.crossesBridge==(id=='garden'))
    end end
    -- A severed bridge must break the eastern connection; proximity to another
    -- street/riverbank must never be treated as a traversable route.
    local broken=Roads.new()
    for i=#broken.segments,1,-1 do if broken.segments[i].bridge then table.remove(broken.segments,i) end end
    local severed=Routes.new(broken)
    check('commute_disconnected_bridge_detected',severed:find('warehouse','garden')==nil)
    check('commute_unknown_address_rejected',routes:find('warehouse','missing')==nil)
end
return Test
