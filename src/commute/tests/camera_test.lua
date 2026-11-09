local Camera = require("src.commute.camera")

local Test = {}
local function near(a, b, epsilon)
    return math.abs(a - b) <= (epsilon or 0.002)
end

function Test.run(check)
    local world = {
        size = 128,
        maxHeight = 20,
        height = function(_, x, z) return 1 + x * 0.035 + z * 0.02 end,
    }
    local actor = { x = 32, z = 32, heading = 0, speed = 0 }
    local camera = Camera.new(actor, world)
    local samples = 0
    local counted = Camera.new(actor, {height=function() samples=samples+1;return 3 end})
    samples = 0
    local suppliedX,suppliedY = counted:screen(40,45,3)
    local suppliedDepth = counted:depth(40,45,3)
    check("commute_camera_cached_heights_skip_terrain_sampling",samples==0)
    local fallbackX,fallbackY = counted:screen(40,45)
    local fallbackDepth = counted:depth(40,45,0/0)
    check("commute_camera_missing_invalid_heights_sample_once",samples==2
        and near(suppliedX,fallbackX) and near(suppliedY,fallbackY)
        and near(suppliedDepth,fallbackDepth))
    local x, z = 41.5, 47.25
    local sx, sy = camera:screen(x, z, world:height(x, z))
    local worldX, worldZ = camera:screenToWorld(sx, sy)
    check("commute_camera_sloped_terrain_round_trip",
        near(worldX, x, 0.01) and near(worldZ, z, 0.01),
        ("expected %.3f, %.3f; got %.3f, %.3f"):format(x, z, worldX, worldZ))

    check("commute_camera_heading_zero_is_east", camera:headingDirection(0) == "east")
    check("commute_camera_orbit_rotates_world_heading", (function()
        camera:orbit(90, 0)
        return camera:headingDirection(0) == "south"
            and camera:relativeDirection("north") == "east"
    end)())

    camera:zoomBy(100000)
    camera:orbit(-721, 1000)
    check("commute_camera_controls_stay_clamped",
        camera.targetZoom == Camera.ZOOM_MAX and camera.tilt == Camera.TILT_MAX
            and camera.yaw >= 0 and camera.yaw < 360)
    camera:zoomBy(-100000)
    camera:orbit(0, -1000)
    check("commute_camera_lower_controls_stay_clamped",
        camera.targetZoom == Camera.ZOOM_MIN and camera.tilt == Camera.TILT_MIN)
end

return Test
