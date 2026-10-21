-- Pixel-space measurements of the approved, unmodified production sprites.
-- All renderers and hit tests share these apertures and camera definitions.
return {
    backgrounds={
        "stop-01-desert-sunset.png","stop-02-wetland.png","stop-03-cactus-desert.png",
        "stop-04-ruined-silhouette.png","stop-05-orange-ruins.png","stop-06-wilderness.png",
        "stop-07-blue-city.png","stop-08-river-forest.png","stop-09-deep-forest.png",
        "stop-10-pale-city.png","stop-11-autumn-forest.png","stop-12-industrial-waste.png",
        "stop-13-salt-flats.png","stop-14-storm-coast.png","stop-15-burned-pine.png",
        "stop-16-ghost-town.png","stop-17-mountain-pass.png",
    },
    relay={width=2001,height=786},
    slots={
        {id="upper_left",x=750,y=236,w=57,h=61},
        {id="upper_right",x=895,y=237,w=54,h=60},
        {id="annex_left",x=588,y=428,w=46,h=51},
        {id="center_door",x=742,y=429,w=74,h=98},
        {id="center_window",x=905,y=430,w=51,h=53},
        {id="loading_bay_left",x=1177,y=450,w=82,h=80},
        {id="loading_bay_right",x=1383,y=452,w=91,h=80},
        {id="side_door",x=1556,y=451,w=40,h=78},
    },
    frames={
        wide={x=239,y=194,w=572,h=374,centerX=525,centerY=381,cover=1},
        tall={x=383,y=196,w=296,h=416,centerX=531,centerY=404,cover=.68},
    },
    -- These bounds stay inside the room shell; its own alpha supplies the
    -- precise curtain, trim and arch edges over each independent window view.
    interiorWindows={
        {id="wide",x=538,y=94,w=192,h=149,cameraOffset=-18},
        {id="tall",x=1084,y=87,w=132,h=156,cameraOffset=18},
    },
    damagePoints={
        wide={{188,283},{184,448},{401,650},{717,649},{852,400}},
        tall={{316,350},{742,454},{451,687},{616,689}},
    },
}
