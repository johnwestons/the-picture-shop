-- Historical registration only. The user rejected articulated sprites; do not integrate.
-- Coordinates are approximate visible joint centers in crop-local pixels, with 18px margin.
return { assetId='commute-rider-rig-east-v1', status='retired_user_rejected_articulated_sprites', runtimeIntegrated=false, gaitApproved=false, parts={
 body={image='parts/body.png',shoulder={x=80,y=268},hip={x=80,y=450}},
 upper_arm_near={image='parts/upper_arm_near.png',pivot={x=180,y=75},distal={x=74,y=194}},
 upper_arm_far={image='parts/upper_arm_far.png',pivot={x=48,y=78},distal={x=138,y=190}},
 forearm_glove_near={image='parts/forearm_glove_near.png',pivot={x=95,y=55},distal={x=145,y=165}},
 forearm_glove_far={image='parts/forearm_glove_far.png',pivot={x=91,y=55},distal={x=141,y=160}},
 thigh_near={image='parts/thigh_near.png',pivot={x=64,y=63},distal={x=163,y=210}},
 thigh_far={image='parts/thigh_far.png',pivot={x=44,y=73},distal={x=145,y=184}},
 shin_boot_near={image='parts/shin_boot_near.png',pivot={x=154,y=66},distal={x=131,y=229},groundOffsetFromAnkle={x=28,y=97},soleContact={x=159,y=326}},
 shin_boot_far={image='parts/shin_boot_far.png',pivot={x=138,y=64},distal={x=124,y=221},groundOffsetFromAnkle={x=18,y=89},soleContact={x=142,y=310}}
}}
