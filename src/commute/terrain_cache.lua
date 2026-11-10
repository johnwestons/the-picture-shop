-- Disposable, versioned CPU mesh cache. The saved town remains authoritative.
-- Tiles are individually addressable so a cold exterior can reveal its local
-- ground without allocating the whole town's GPU meshes.
local Town=require('src.commute.town')
local TerrainMesh=require('src.commute.terrain_mesh')
local Cache={VERSION=2}
local vertexFormat='<'..string.rep('f',24)
local headerFormat='<I4I4I4I4I4'
local headerBytes=4+20+32
local magic='TPS1'

local function storeFor(town,spacing)
    if not town then return nil end
    spacing=spacing or 1
    local fingerprint=Town.fingerprint(town)
    local variant=spacing==1 and '' or '-spacing-'..tostring(spacing)
    local marker=magic..'|'..tostring(town.id)..'|'..fingerprint..'|484'
    if spacing~=1 then marker=marker..'|spacing='..tostring(spacing) end
    local directory='terrain-cache/v'..Cache.VERSION..variant..'-'..fingerprint
    return {directory=directory,fingerprint=fingerprint,id=town.id,spacing=spacing,marker=marker}
end

function Cache.store(world,spacing)
    return world and storeFor(world.town,spacing) or nil
end

function Cache.available(store)
    return store and love.filesystem.read(store.directory..'/complete.txt')==store.marker or false
end

local function path(store,tile)
    return store.directory..'/'..tile.x0..'-'..tile.z0..'.bin'
end

local function encode(vertices,indices)
    local parts={}
    for i,vertex in ipairs(vertices) do
        assert(#vertex==24,'Unexpected cached terrain vertex width')
        parts[i]=love.data.pack('string',vertexFormat,unpack(vertex))
    end
    local vertexBytes=table.concat(parts)
    -- The existing mesh API uses one-based Lua indices; binary vertex maps use zero-based indices.
    -- Repack indices as zero-based values in one call rather than retaining Lua tables on disk.
    local zero={}
    for i,index in ipairs(indices) do zero[i]=index-1 end
    local indexBytes=love.data.pack('string','<'..string.rep('I4',#zero),unpack(zero))
    return vertexBytes..indexBytes
end

function Cache.writeTile(store,tile,vertices,indices)
    if not store then return false,'no_store' end
    local ok,reason=pcall(function()
        local created=love.filesystem.createDirectory(store.directory)
        if not created then
            local info=love.filesystem.getInfo(store.directory)
            assert(info and info.type=='directory','Unable to create terrain cache directory')
        end
        local body=encode(vertices,indices)
        local compressed=love.data.compress('string','lz4',body)
        local useCompression=#compressed<#body
        local payload=useCompression and compressed or body
        local digest=love.data.hash('sha256',body)
        local header=magic..love.data.pack('string',headerFormat,#vertices,#indices,#body,#payload,useCompression and 1 or 0)..digest
        assert(love.filesystem.write(path(store,tile),header..payload))
    end)
    return ok,ok and nil or tostring(reason)
end

function Cache.readTile(store,tile,manifestChecked)
    if not manifestChecked and not Cache.available(store) then return nil,'cache_incomplete' end
    local source=love.filesystem.read(path(store,tile))
    if not source or #source<headerBytes or source:sub(1,4)~=magic then return nil,'tile_missing' end
    local okay,result=pcall(function()
        local vertexCount,indexCount,rawBytes,payloadBytes,compressed=love.data.unpack(headerFormat,source,5)
        if vertexCount~=(tile.nx+1)*(tile.nz+1) or indexCount~=tile.nx*tile.nz*6
            or rawBytes~=vertexCount*96+indexCount*4 or payloadBytes~=#source-headerBytes
            or compressed~=0 and compressed~=1 then return nil end
        local digest=source:sub(25,56)
        local payload=source:sub(57)
        local body=compressed==1 and love.data.decompress('string','lz4',payload) or payload
        if #body~=rawBytes or love.data.hash('sha256',body)~=digest then return nil end
        local vertices=love.data.newByteData(body:sub(1,vertexCount*96))
        local indices=love.data.newByteData(body:sub(vertexCount*96+1))
        return {vertices=vertices,indices=indices,vertexCount=vertexCount,indexCount=indexCount}
    end)
    if not okay or not result then return nil,'tile_corrupt' end
    return result
end

function Cache.complete(store,mesh)
    if not store or not mesh or not mesh.ready or mesh.total~=484 then return false end
    return love.filesystem.write(store.directory..'/complete.txt',store.marker)==true
end

function Cache.bake(town,spacing)
    if not spacing then
        local mobile=love.system.getOS()=='Android' or os.getenv('PICTURE_SHOP_TERRAIN_FORCE_MOBILE')=='1'
        spacing=mobile and TerrainMesh.MOBILE_SPACING or 1
    end
    local world=Town.world(town)
    local store=Cache.store(world,spacing)
    local job={world=world,store=store,mesh=TerrainMesh.new(world,{tileSize=24,spacing=spacing}),
        done=Cache.available(store),failed=false}
    function job:step(seconds)
        if self.done then return true end
        self.mesh:step(seconds or .008,function(tile,vertices,indices)
            if not self.failed then
                local okay=Cache.writeTile(self.store,tile,vertices,indices)
                if not okay then self.failed=true end
            end
        end,love.timer.getTime)
        if self.failed or self.mesh.ready then
            self.done=true
            if not self.failed then self.failed=not Cache.complete(self.store,self.mesh) end
        end
        return self.done
    end
    function job:progress()
        return self.done and 1 or self.mesh.completed/self.mesh.total
    end
    return job
end

return Cache
