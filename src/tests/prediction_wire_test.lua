local Test={}
function Test.run(check)
    local Wire=require('src.net.prediction_wire')
    local Protocol=require('src.net.protocol')
    local Codec=require('src.net.codec')
    local P=require('src.commute.prediction')
    local Copy=require('src.net.shop_replication').copy
    local known=string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,240,63,0,0,0,0,0,0,4,192)
    local bytes=assert(Wire.pack({0,1,-2.5}))
    local decoded=assert(Wire.unpack(known,3))
    check('prediction_wire_has_explicit_cross_platform_little_endian_double_layout',bytes==known
        and decoded[1]==0 and decoded[2]==1 and decoded[3]==-2.5)
    local tiny=assert(Wire.unpack(string.char(1,0,0,0,0,0,0,0),1))
    check('prediction_wire_retains_smallest_subnormal_double',tiny[1]>0
        and assert(Wire.pack(tiny))==string.char(1,0,0,0,0,0,0,0))
    check('prediction_wire_rejects_truncation_extra_data_and_unbounded_vectors',
        not Wire.unpack(known:sub(2),3) and not Wire.unpack(known..'x',3)
        and not Wire.unpack(string.rep('x',520),65) and not Wire.pack({})
        and not Wire.pack({[1]=1,[3]=2}) and not Wire.pack({[1]=1,extra=2}))
    local large={};for i=1,65 do large[i]=i end
    check('prediction_wire_has_a_hard_64_double_512_byte_ceiling',not Wire.pack(large))
    large[65]=nil
    check('prediction_wire_accepts_maximum_bounded_vector',#assert(Wire.pack(large))==512)

    local rawMax,wireMax=0,0
    local function raw(packet)
        return packet:sub(1,#Protocol.SHOP_COMPRESSION_MAGIC)==Protocol.SHOP_COMPRESSION_MAGIC
            and love.data.decompress('string','lz4',packet:sub(#Protocol.SHOP_COMPRESSION_MAGIC+1))or packet
    end
    local function payload(mode)
        local values={}
        local numbers={math.pi,1/3,math.sqrt(2),1e-200,1e12,-1e12}
        for i,field in ipairs(P.fields[mode])do
            values[i]=P.booleans[field] and (i%2) or field=='gear'and 1 or numbers[(i-1)%#numbers+1]
        end
        return {sessionId=string.rep('s',64),serverTick=4294967295,playerId=4,sequence=4294967295,
            key=string.rep('k',64),mode=mode,part=1,values=Codec.array(values)}
    end
    for mode,names in pairs(P.fields)do
        local input=payload(mode);local original=Copy(input)
        local packet=assert(Protocol.encode('prediction_snapshot',input))
        local result=assert(Protocol.decode(packet))
        local wire=assert(Codec.decode(raw(packet)))
        rawMax=math.max(rawMax,#raw(packet));wireMax=math.max(wireMax,#packet)
        check('prediction_wire_'..mode..'_all_fields_round_trip_without_quantization',
            require('src.net.shop_replication').equal(result.payload,original)
            and require('src.net.shop_replication').equal(input,original))
        check('prediction_wire_'..mode..'_complete_checkpoint_fits_one_packet',#names<=P.PART_VALUES
            and type(wire.payload.values)=='string'and #wire.payload.values==#names*8
            and #packet<=Protocol.MAX_PACKET_BYTES and #raw(packet)<=Protocol.MAX_PACKET_BYTES)
        local api=assert(Protocol.make('prediction_snapshot',input))
        check('prediction_wire_'..mode..'_public_api_keeps_numeric_values',Codec.isArray(api.payload.values)
            and api.payload.values[1]==input.values[1])
        input.part=2
        check('prediction_wire_'..mode..'_rejects_unneeded_extra_part',not Protocol.encode('prediction_snapshot',input))
    end
    check('prediction_wire_worst_case_metadata_stays_below_mtu',rawMax<=900 and wireMax<=900,
        'largest raw='..rawMax..' wire='..wireMax)

    local input=payload('bike')
    local packet=assert(Protocol.encode('prediction_snapshot',input))
    local original=assert(Codec.decode(raw(packet)))
    local function rejected(change)
        local value=Copy(original);change(value)
        return Protocol.decode(assert(Codec.encode(value)))==nil
    end
    check('prediction_wire_rejects_legacy_numeric_array_representation',rejected(function(v)v.payload.values=input.values end))
    check('prediction_wire_rejects_noncanonical_negative_zero',rejected(function(v)
        v.payload.values=string.char(0,0,0,0,0,0,0,128)..v.payload.values:sub(9)
    end))
    local invalidNumbers=true
    for _,value in ipairs({math.huge,-math.huge,0/0,1e12+1})do
        invalidNumbers=invalidNumbers and rejected(function(v)
            v.payload.values=love.data.pack('string','<d',value)..v.payload.values:sub(9)
        end)
    end
    check('prediction_wire_rejects_nonfinite_and_out_of_range_binary_values',invalidNumbers)
    check('prediction_wire_rejects_short_long_and_nonstring_values',
        rejected(function(v)v.payload.values=v.payload.values:sub(2)end)
        and rejected(function(v)v.payload.values=v.payload.values..string.rep('x',8)end)
        and rejected(function(v)v.payload.values=false end))
    local validFields=true
    for i,field in ipairs(P.fields.bike)do
        if P.booleans[field] or field=='gear' then
            validFields=validFields and rejected(function(v)
                local invalid=P.booleans[field] and .5 or 0
                v.payload.values=v.payload.values:sub(1,(i-1)*8)..love.data.pack('string','<d',invalid)..v.payload.values:sub(i*8+1)
            end)
        end
    end
    check('prediction_wire_retains_boolean_and_gear_field_validation',validFields)
    check('prediction_wire_rejects_old_protocol_before_binary_decode',Protocol.VERSION==82
        and rejected(function(v)v.version=81 end)and rejected(function(v)v.version=80 end))

    local compress=love.data.compress
    love.data.compress=nil
    local okay,uncompressed=pcall(Protocol.encode,'prediction_snapshot',input)
    love.data.compress=compress
    check('prediction_wire_compression_is_optional_and_lossless',okay and uncompressed
        and #uncompressed<=Protocol.MAX_PACKET_BYTES and Protocol.decode(uncompressed)~=nil)
    local idle=payload('bike')
    for i,field in ipairs(P.fields.bike)do idle.values[i]=field=='gear'and 1 or 0 end
    local small=assert(Protocol.encode('prediction_snapshot',idle))
    check('prediction_wire_compresses_repeated_values_without_changing_fields',
        small:sub(1,#Protocol.SHOP_COMPRESSION_MAGIC)==Protocol.SHOP_COMPRESSION_MAGIC
        and #small+64<=#raw(small)and require('src.net.shop_replication').equal(assert(Protocol.decode(small)).payload,idle),
        'raw='..#raw(small)..' compressed='..#small)
end
return Test
