local Options={}
Options.fields={
    {'roads','Road density',{'Country road','Neighborhood','Downtown'},2},
    {'elevation','Elevation',{'Lowland','Rolling','Mountainous'},2},
    {'biome','Ground biome',{'Grassland','Woodland','Desert'},2},
    {'trees','Trees',{'None','Sparse','Medium','Dense'},3},
    {'brush','Undergrowth',{'None','Sparse','Medium','Dense'},3},
    {'trails','Trail density',{'None','Low','Medium','High'},3},
    {'length','Trail length',{'Shortcut','Mixed','Long ride'},2},
    {'river','Waterways',{'Fordable creek','One river','Wide river','Watershed'},2},
}
Options.species={}
for kind in pairs(require('src.commute.flora').scales) do
    if kind~='stone' and kind~='rock' then table.insert(Options.species,kind) end
end
table.sort(Options.species)
function Options.copy(input)
    local out={excluded={}}
    for _,field in ipairs(Options.fields) do
        local value=input and input[field[1]] or field[4]
        assert(type(value)=='number' and value%1==0 and field[3][value],'Invalid '..field[2])
        out[field[1]]=value
    end
    for _,kind in ipairs(Options.species) do
        if input and input.excluded and input.excluded[kind]==true then out.excluded[kind]=true end
    end
    return out
end
function Options.valid(input)
    if type(input)~='table' or type(input.excluded)~='table' then return false end
    local ok,normalized=pcall(Options.copy,input)
    if not ok then return false end
    for _,field in ipairs(Options.fields) do
        if input[field[1]]~=normalized[field[1]] then return false end
    end
    for kind,value in pairs(input.excluded) do
        if value~=true or not normalized.excluded[kind] then return false end
    end
    return true
end
return Options
