local Guide={}
Guide.MIN_VISIBLE_MARGIN=6
local edges={"top","right","bottom","left"}
function Guide.marginPixels(margin,size,inches)
    if not margin or margin<=0 then return 0 end
    return math.min(size*.45,math.max(Guide.MIN_VISIBLE_MARGIN,margin/math.max(.01,inches)*size))
end
function Guide.current(paper,programIndex)
    local cut=paper and paper.cuts and paper.cuts[paper.activeCut]
    if not cut or paper.offSpec then return nil end
    local original
    for i,edge in ipairs(edges) do if edge==cut.edge then original=i end end
    if not original then return nil end
    local turns=math.floor((paper.orientation or 0)%360/90)
    return {number=paper.activeCut,edge=cut.edge,screenEdge=edges[(original-1+turns)%4+1],
        margin=cut.margin,gauge=cut.gauge,rotationReady=(paper.orientation or 0)%360==cut.orientation,
        programReady=programIndex==nil or programIndex==paper.activeCut}
end
function Guide.band(guide,x,y,width,height,widthInches,heightInches)
    if not guide or not guide.margin or guide.margin<=0 then return nil end
    local side=guide.screenEdge
    local vertical=side=="left" or side=="right"
    local size=vertical and width or height
    local inches=vertical and widthInches or heightInches
    local trim=Guide.marginPixels(guide.margin,size,inches)
    if side=="left" then return {x=x,y=y,width=trim,height=height} end
    if side=="right" then return {x=x+width-trim,y=y,width=trim,height=height} end
    if side=="top" then return {x=x,y=y,width=width,height=trim} end
    return {x=x,y=y+height-trim,width=width,height=trim}
end
return Guide
