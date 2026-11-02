-- Registration for the eight authored home sink-action views.
local R={
    order={"east","southeast","south","southwest","west","northwest","north","northeast"},
    cellWidth=384,cellHeight=512,bodyScale=.175,views={},
    bodyFiles={
        wash={"wash-phase-a.png","wash-phase-b.png"},
        dishes={"dishes-phase-a.png","dishes-phase-b.png"},
        cupwash={"cup-scrub.png","cup-hold.png"},
        cupfill={"cup-hold.png"},
    },
    fps={wash=4,dishes=5,cupwash=4,cupfill=1},
    propScale={plate=.070,mug=.065},
}

-- Source-local hand centres, read from the authored 384x512 cells. A second
-- centre allows the body fingers to be restored over plates and mugs.
local washHands={
    {{274,270},{254,284}},{{270,270},{250,284}},{{204,285},{178,285}},{{132,270},{110,284}},
    {{128,270},{108,284}},{{128,270},{108,284}},{{204,290},{178,290}},{{274,270},{254,284}},
}
local dishHands={
    {{282,291},{261,301}},{{278,287},{258,300}},{{204,300},{180,300}},{{126,287},{106,300}},
    {{124,291},{103,301}},{{124,287},{104,300}},{{204,300},{180,300}},{{282,287},{261,300}},
}
local cupHands={
    {{274,272},{253,287}},{{273,272},{253,287}},{{204,288},{180,288}},{{131,272},{111,287}},
    {{128,272},{107,287}},{{128,272},{107,287}},{{204,290},{180,290}},{{274,272},{253,287}},
}
for index,direction in ipairs(R.order) do
    local column=(index-1)%4;local row=math.floor((index-1)/4)
    R.views[direction]={
        index=index,column=column,row=row,sourceX=column*R.cellWidth,sourceY=row*R.cellHeight,
        foot={192,478},rear=direction=="north" or direction=="northeast" or direction=="northwest",
        hands={wash=washHands[index],dishes=dishHands[index],cupwash=cupHands[index],cupfill=cupHands[index]},
    }
end
return R
