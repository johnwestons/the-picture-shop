-- Fixed inland commute town terrain. The procedural source is pinned under
-- src.commute.vendor so this world stays independent of the wildlife game.
local Config=require('src.commute.vendor.world_config')
local Plan=require('src.commute.vendor.island_plan')

local Terrain={SEED=4261,SIZE=512}

function Terrain.new()
    local seed=Terrain.SEED
    local config={size=Terrain.SIZE,center=Terrain.SIZE/2,radius=201}
    local plan=Plan.newTown(seed,config)
    local world={seed=seed,size=config.size,config=config,streamed=true,
        maxHeight=Config.HEIGHT_LIMIT,spawn={x=config.center,z=config.center},
        plan=plan,terrain=plan,river=plan.rivers[1],
        waterLevel=0,playableBounds=plan.playableBounds,
        bridgeCrossing=plan.bridgeCrossing}

    function world:height(x,z)
        return self.plan:height(x,z)
    end

    -- Raw height includes the river cut; baseHeight is the uncut land relief.
    function world:rawHeight(x,z)
        return self.plan:rawHeight(x,z)
    end

    function world:baseHeight(x,z)
        return self.plan:landHeight(x,z)
    end

    function world:habitat(x,z)
        return self.plan:habitat(x,z)
    end

    function world:riverDistance(x,z)
        return self.plan:riverDistance(x,z)
    end

    function world:riverCenterX(z)
        return self.plan:riverCenterX(z)
    end

    return world
end

return Terrain
