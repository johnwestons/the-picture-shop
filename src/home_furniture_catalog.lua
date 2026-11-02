local Catalog={ORDER={"bed","chair","couch","mini_fridge","small_desk","floor_lamp","clock","laptop","cup","stove","refrigerator","countertop","kitchen_table","bedside_table","coffee_table","desk_lamp"},DIRECTIONS={"east","southeast","south","southwest","west","northwest","north","northeast"}}
Catalog.ITEMS={
    bed={name="Plain single bed",length=96,width=42,height=55,priceCents=15000,shippingCents=1000,minutes=120,
        dimensions="2.0 m x 0.9 m",art="bed-eight-directions.png",scale=.28,
        frames={southeast=1,south=2,southwest=3,east=4,northwest=5,north=6,northeast=7,west=8},
        pivots={{228,370},{128,370},{224,370},{180,335},{228,335},{128,340},{224,335},{180,330}}},
    chair={name="Worn kitchen chair",length=24,width=24,height=52,priceCents=2500,shippingCents=500,minutes=120,
        dimensions="0.5 m x 0.5 m",art="chair-eight-directions.png",scale=.16,
        frames={southeast=1,south=2,southwest=3,west=4,northeast=5,north=6,northwest=7,east=8},
        pivots={{205,370},{192,385},{168,370},{192,385},{205,310},{192,325},{168,310},{192,325}}},
}
local front={southeast=1,south=2,southwest=3,east=4,northwest=5,north=6,northeast=7,west=8}
local reverse={southwest=1,south=2,southeast=3,east=4,northeast=5,north=6,northwest=7,west=8}
Catalog.ITEMS.couch={name="Worn two-seat couch",length=42,width=76,height=65,priceCents=9500,shippingCents=1000,minutes=120,
    dimensions="1.6 m x 0.9 m",art="couch-eight-directions.png",scale=.24,frames=front,
    columns={{0,416},{416,368},{784,384},{1168,368}},
    pivots={{210,365},{178,370},{194,365},{189,365},{210,340},{178,330},{194,340},{189,345}}}
Catalog.ITEMS.mini_fridge={name="Old mini fridge",length=28,width=28,height=52,priceCents=8000,shippingCents=750,minutes=120,capacity=24,
    dimensions="0.6 m x 0.6 m",art="mini-fridge-eight-directions.png",scale=.17,frames=front,
    pivots={{200,385},{190,400},{190,385},{195,400},{195,365},{190,380},{190,365},{195,385}}}
Catalog.ITEMS.small_desk={name="Small wooden desk",length=28,width=48,height=44,priceCents=6000,shippingCents=750,minutes=120,
    dimensions="1.0 m x 0.6 m",art="small-desk-eight-directions.png",scale=.20,frames=reverse,
    pivots={{180,350},{195,380},{210,350},{210,350},{190,350},{190,380},{205,350},{210,350}},
    surface={height=34,slots={{-4,-8},{-7,17},{10,17}}}}
Catalog.ITEMS.floor_lamp={name="Old brass floor lamp",length=20,width=20,height=90,priceCents=2000,shippingCents=500,minutes=120,
    light={height=62,radius=1},
    dimensions="0.4 m round base",art="floor-lamp-eight-directions.png",scale=.20,frames=front,
    pivots={{198,450},{192,450},{190,450},{192,450},{198,450},{192,450},{190,450},{192,450}}}
Catalog.ITEMS.clock={name="Bedside digital clock",length=6,width=12,height=12,priceCents=1200,shippingCents=300,minutes=120,
    dimensions="Desk / counter / floor",art="clock-eight-directions.png",scale=.065,frames=reverse,small=true,
    pivots={{195,370},{195,380},{195,370},{210,360},{195,325},{195,340},{195,325},{210,325}}}
Catalog.ITEMS.laptop={name="Used laptop",length=14,width=20,height=23,priceCents=18000,shippingCents=500,minutes=120,
    dimensions="Desk / counter / floor",art="laptop-eight-directions.png",scale=.085,small=true,
    frames={southeast=1,south=2,southwest=3,west=4,northwest=5,north=6,northeast=7,east=8},
    pivots={{195,390},{195,390},{195,390},{195,390},{192,360},{192,360},{192,360},{192,360}}}
Catalog.ITEMS.cup={name="Plain ceramic mug",length=5,width=5,height=10,priceCents=300,shippingCents=200,minutes=120,
    dimensions="Desk / counter / floor",art="cup-eight-directions.png",scale=.035,small=true,frames=front,
    pivots={{198,405},{192,405},{190,405},{192,405},{198,405},{192,405},{192,405},{192,405}}}
Catalog.ITEMS.stove={name="Used electric stove",length=32,width=32,height=65,priceCents=14000,shippingCents=1000,minutes=120,hookup="stove",hookupDirection="west",defaultDirection="west",
    dimensions="Kitchen hookup / face left",art="stove-eight-directions.png",scale=.17,frames=front,
    pivots={{195,410},{192,420},{192,410},{210,420},{195,400},{192,415},{192,400},{210,420}}}
Catalog.ITEMS.refrigerator={name="Old full-size fridge",length=32,width=32,height=90,priceCents=16000,shippingCents=1200,minutes=120,capacity=60,hookup="refrigerator",hookupDirection="south",defaultDirection="south",
    dimensions="Kitchen hookup / face south / 60 portions",art="refrigerator-eight-directions.png",scale=.18,frames=front,
    pivots={{195,420},{192,435},{192,420},{195,435},{195,420},{192,435},{192,420},{195,435}}}
Catalog.ITEMS.countertop={name="Kitchen base cabinet",length=30,width=48,height=50,priceCents=6500,shippingCents=750,minutes=120,
    dimensions="0.9 m x 0.6 m / work surface",art="countertop-eight-directions.png",scale=.20,frames=front,
    columns={{0,416},{416,368},{784,432},{1216,320}},
    pivots={{195,400},{178,410},{176,400},{156,420},{195,400},{178,410},{176,400},{156,420}},
    surface={height=45,slots={{-4,-12},{-4,12},{9,0}}}}
Catalog.ITEMS.kitchen_table={name="Small kitchen table",length=40,width=60,height=42,priceCents=5500,shippingCents=750,minutes=120,
    dimensions="1.2 m x 0.8 m / chairs sold separately",art="kitchen-table-eight-directions.png",scale=.22,frames=front,
    columns={{0,416},{416,376},{792,432},{1224,312}},
    pivots={{200,385},{178,370},{171,385},{158,400},{200,385},{178,370},{171,385},{158,400}},
    surface={height=37,slots={{0,-18},{0,18},{-10,0}}}}
Catalog.ITEMS.bedside_table={name="Worn bedside table",length=24,width=24,height=42,priceCents=3000,shippingCents=500,minutes=120,
    dimensions="0.5 m square / 2 surface slots",art="bedside-table-eight-directions.png",scale=.12,frames=front,
    pivots={{208,400},{202,400},{180,400},{184,400},{208,362},{202,362},{180,362},{184,370}},
    surface={height=31,slots={{0,-8},{0,8}}}}
Catalog.ITEMS.coffee_table={name="Low wooden coffee table",length=28,width=56,height=35,priceCents=4000,shippingCents=500,minutes=120,
    dimensions="1.1 m x 0.55 m / 3 surface slots",art="coffee-table-eight-directions.png",scale=.18,frames=reverse,
    columns={{0,416},{416,408},{824,408},{1232,304}},
    pivots={{212,350},{204,333},{204,350},{152,357},{212,300},{204,283},{204,300},{152,307}},
    surface={height=24,slots={{0,-16},{0,16},{-6,0}}}}
Catalog.ITEMS.desk_lamp={name="Old adjustable desk lamp",length=10,width=10,height=28,priceCents=1500,shippingCents=500,minutes=120,
    dimensions="Desk / table / counter / floor",art="desk-lamp-eight-directions.png",scale=.065,frames=front,small=true,
    columns={{0,416},{416,352},{768,384},{1152,384}},
    pivots={{184,450},{160,450},{247,450},{150,450},{225,438},{160,438},{152,438},{247,438}},
    light={radius=.42,points={{302,212},{160,212},{112,212},{265,210},{123,190},{160,190},{237,190},{118,200}}}}
Catalog.ORDER[#Catalog.ORDER+1]="desk"
Catalog.ORDER[#Catalog.ORDER+1]="guest_mat"
Catalog.ITEMS.desk={name="Full wooden desk",length=34,width=70,height=50,priceCents=10000,shippingCents=750,minutes=120,
    dimensions="1.4 m x 0.65 m / 3 surface slots",art="desk-eight-directions.png",scale=.21,frames=reverse,
    columns={{0,416},{416,400},{816,432},{1248,288}},
    pivots={{212,410},{199,406},{204,405},{142,430},{212,334},{199,326},{204,334},{142,345}},
    surface={height=40,slots={{0,-20},{0,20},{-8,0}}}}
Catalog.ITEMS.guest_mat={name="Thin guest sleeping mat",length=96,width=32,height=8,priceCents=3500,shippingCents=500,minutes=120,
    dimensions="1.9 m x 0.65 m / one sleeper",art="guest-mat-eight-directions.png",scale=.25,frames=front,
    columns={{0,416},{416,272},{688,432},{1120,416}},
    frameScaleY={.80,.72,.80,.85,.72,.65,.74,.85},
    pivots={{225,287},{144,278},{230,287},{200,289},{225,232},{144,218},{230,232},{200,247}}}
local utilityFront={southeast=1,south=2,southwest=3,west=4,northwest=5,north=6,northeast=7,east=8}
for _,kind in ipairs({"wardrobe","cabinet","old_tv","trash_can"}) do Catalog.ORDER[#Catalog.ORDER+1]=kind end
Catalog.ITEMS.wardrobe={name="Worn wooden wardrobe",length=26,width=44,height=95,priceCents=9000,shippingCents=1000,minutes=120,
    dimensions="0.9 m x 0.5 m / 8 clean bundles",art="wardrobe-eight-directions.png",scale=.21,frames=utilityFront,
    pivots={{224,426},{208,423},{189,426},{192,441},{208,401},{196,424},{197,401},{194,441}},
    storage={key="clean",capacity=8}}
Catalog.ITEMS.cabinet={name="Old pantry cabinet",length=24,width=40,height=65,priceCents=5000,shippingCents=750,minutes=120,
    dimensions="0.8 m x 0.4 m / 32 food portions",art="cabinet-eight-directions.png",scale=.15,frames=utilityFront,capacity=32,
    rows={{0,480},{480,544}},
    pivots={{215,406},{208,421},{208,406},{207,436},{215,418},{208,423},{208,418},{207,443}}}
Catalog.ITEMS.old_tv={name="Old woodgrain TV",length=24,width=28,height=35,priceCents=4500,shippingCents=500,minutes=120,
    dimensions="Table / counter / floor",art="old-tv-eight-directions.png",scale=.105,frames=utilityFront,small=true,television=true,
    pivots={{205,412},{198,410},{200,412},{218,415},{205,333},{198,335},{200,333},{218,350}},
    screen={{{151,279},{302,240},{302,371},{151,411}},{{80,247},{260,247},{260,377},{80,377}},{{54,242},{202,281},{202,403},{54,365}}}}
Catalog.ITEMS.trash_can={name="Old pedal trash can",length=18,width=18,height=35,priceCents=1500,shippingCents=500,minutes=120,
    dimensions="0.3 m x 0.35 m / 16 waste portions",art="trash-can-eight-directions.png",scale=.09,frames=utilityFront,
    pivots={{212,419},{199,428},{198,419},{198,428},{212,411},{199,418},{198,411},{198,408}},
    storage={key="trash",capacity=16}}
function Catalog.angle(direction)
    for i,d in ipairs(Catalog.DIRECTIONS) do if d==direction then return (i-1)*math.pi/4 end end
end
function Catalog.rotate(direction,step)
    for i,d in ipairs(Catalog.DIRECTIONS) do if d==direction then return Catalog.DIRECTIONS[(i-1+(step or 1))%8+1] end end
    return "southeast"
end
return Catalog
