local Art=require('src.commute.normal_art')
local Camera=require('src.commute.camera')
local Test={}
function Test.run(check)
    local world=require('src.commute.roads').new():attach(require('src.commute.terrain').new())
    local camera=Camera.new({x=100,z=380},world);camera.yaw=0
    local directions={'north','northeast','east','southeast','south','southeast','east','northeast'}
    local headings={-math.pi/2,-math.pi/4,0,math.pi/4,math.pi/2,math.pi*.75,math.pi,math.pi*1.25}
    local passed=true
    for i,angle in ipairs(headings) do
        local actor={heading=angle,speed=1,distance=.65}
        local action,mirror,distance=Art.selection(actor,camera)
        local suffix=directions[i]=='east' and '' or '_'..directions[i]
        passed=passed and action=='walk'..suffix and mirror==(i>5 and -1 or 1) and distance==.65
        actor.speed=0
        local idle,idleMirror=Art.selection(actor,camera)
        passed=passed and idle=='idle'..suffix and idleMirror==mirror
    end
    check('commute_normal_avatar_walk_and_idle_cover_camera_relative_directions',passed)
    camera:orbit(90,0)
    check('commute_normal_avatar_camera_orbit_changes_view',Art.selection({heading=0,speed=0},camera)=='idle_south')
    local action,_,distance=Art.selection({heading=0,speed=0,distance=0},camera,{speed=1,distance=.91})
    check('commute_normal_avatar_uses_remote_resolved_motion',action=='walk_south' and distance==.91)
    local a=Art.appearance({character='rabbit-worker',furColorway=2,overallsColorway=3})
    check('commute_normal_avatar_preserves_selected_colors',a.furColorway==2 and a.overallsColorway==3 and Art.valid(a))
    a.character='missing-character'
    check('commute_normal_avatar_rejects_unknown_saved_character',not Art.valid(a))
    check('commute_normal_avatar_legacy_appearance_defaults_safely',Art.valid(nil) and Art.valid(Art.appearance(nil)))
end
return Test
