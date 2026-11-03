-- Versioned inland commute town terrain. The procedural source is pinned under
-- src.commute.vendor so this world stays independent of the wildlife game.
local Config=require('src.commute.vendor.world_config')
local Plan=require('src.commute.vendor.island_plan')

local Terrain={SEED=4261,SIZE=512}

function Terrain.new(options)
    options=options or {}
    local seed=options.seed or Terrain.SEED
    local size=options.size or Terrain.SIZE
    local config={size=size,center=size/2,radius=201}
    local v2=options.mode=='inland-town-v2'
    local plan=v2 and require('src.commute.town_terrain_v2').new(options,config) or Plan.newTown(seed,config)
    -- Saved towns pin the sampled relief instead of re-rolling it on load.
    -- The immutable inland-town-v1 analytical river/detail code is retained.
    if options.heights and not v2 then
        local cells=size/Config.COARSE;local index=0
        assert(#options.heights==(cells+1)^2,'Invalid saved town terrain')
        for x=0,cells do for z=0,cells do
            index=index+1;plan.grid[x][z]=options.heights[index]
        end end
    end
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

    function world:sweepObstacles(x,z,nx,nz,radius,bottom,top)
        -- The renderer shares this cache. Headless simulation still resolves
        -- nearby trunks/rocks before they have ever been requested for draw.
        self.vegetation=self.vegetation or require('src.commute.vegetation').new(self)
        return self.vegetation:sweepObstacles(x,z,nx,nz,radius,bottom,top,self.calendar)
    end

    return world
end

return Terrain
