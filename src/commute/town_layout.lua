-- Versioned authored layout retained for legacy shops. Seeded towns save their own definitions.
local destinations={
    warehouse={x=100,z=380,h=4.5,label='The Picture Shop'},
    ['brick-walkup']={x=225,z=330,h=4.5,label='Brick walk-up'},
    garden={x=425,z=208,h=6,label='East Bank garden apartment'},
    courtyard={x=187,z=226,h=9,label='Woodland courtyard'},
    corner={x=110,z=130,h=12,label='Ridge corner apartment'},
}
local definitions={
    {id='shop-lane',width=5,points={{100,380,4.5},{112,372,4.8},{130,360,5}}},
    {id='valley-road',width=6.4,points={{130,360,5},{165,327,5},{205,306,4.5},{250,290,4}}},
    {id='ridge-loop',width=5.6,points={{250,290,4},{250,235,5.5},{220,190,7},{190,155,8},{140,160,10},{112,215,12},{108,280,9},{130,360,5}}},
    {id='east-bank',width=5,points={{250,290,4},{280,270,3.6},{290,270,3.6},{308,270,3.6},{352,270,3.6},{380,270,3.6},{402,240,4.5},{425,208,6}}},
    {id='brick-lane',width=4.2,points={{205,306,4.5},{213,320,4.5},{225,330,4.5}}},
    {id='courtyard-lane',width=4.2,points={{112,215,12},{155,220,10},{187,226,9}}},
    {id='corner-lane',width=4.2,points={{140,160,10},{124,143,11},{110,130,12}}},
}
return {id="original-valley",version=3,size=512,bounds={x0=56,z0=56,x1=458,z1=458},
    destinations=destinations,roads=definitions}
