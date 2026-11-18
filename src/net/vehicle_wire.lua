-- Fixed-layout vehicle view metadata. Public snapshots retain named fields and
-- full numeric precision. Motion numbers use bounded IEEE doubles, as physics
-- checkpoints do, rather than repeatedly spelling them as decimal strings.
local Codec=require('src.net.codec')
local Binary=require('src.net.prediction_wire')
local Wire={}
local motionFields={
    bike={'heading','speed','steer','brake'},
    truck={'heading','speed','steer','brake','throttle','h','pitch'},
}
function Wire.pack(kind,record)
    local motion={}
    for index,key in ipairs(motionFields[kind])do motion[index]=record[key]end
    local bytes,err=Binary.pack(motion)
    if not bytes then return nil,err end
    return Codec.array(kind=='bike'and {record.token,bytes}or {record.token,record.model,record.reverse,bytes})
end
function Wire.unpack(kind,values)
    local size=kind=='bike'and 2 or 4
    if not Codec.isArray(values)or #values~=size then return nil end
    local count=0
    for key in pairs(values)do
        if type(key)~='number'or key%1~=0 or key<1 or key>size then return nil end
        count=count+1
    end
    if count~=size then return nil end
    local motion=Binary.unpack(values[size],#motionFields[kind])
    if not motion then return nil end
    local record={token=values[1]}
    if kind=='truck'then record.model,record.reverse=values[2],values[3]end
    for index,key in ipairs(motionFields[kind])do record[key]=motion[index]end
    return record
end
return Wire
