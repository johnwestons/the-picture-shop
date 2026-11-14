-- Keep player-facing release notes here, newest version first.
return {
    {
        version = "0.1.0-android.115",
        date = "Nov 14, 2026",
        title = "Delivery and mobile usability update",
        changes = {
            "Receiving deliveries now lets employees sign between queued tasks and walk over to meet the driver; the unloading menu confirms when the truck is empty and ready to close.",
            "The work phone directory, bike cargo access, and mobile action controls have been restored and refined.",
            "Vehicle fuel use, delivery mileage, and commute movement and animation speeds have been tuned.",
            "Android 115 carries the delivery, phone, bike cargo, commute, and warehouse improvements in this update.",
        },
    },
    {
        version = "0.1.0-android.114",
        date = "Nov 13, 2026",
        title = "Progressive shop restoration update",
        changes = {
            "The shop floor is cleaned by steering the animated mop over two large spills; each pass visibly fades the water and saves progress.",
            "The restoration checklist tracks spill cleanup automatically. Breaker repair, lights, and utility calls are direct actions, and wall repainting is removed.",
            "The shop landline works without building power. Call the power and water utilities to restore service, then use the repaired breaker to switch on the lights.",
            "The selected restored warehouse image is now the base artwork, with a matching lights-off version.",
            "Windows and Android share release 114 and multiplayer protocol 75.",
        },
    },
    {
        version = "0.1.0-android.111",
        date = "Nov 12, 2026",
        title = "Warehouse restoration and barn controls update",
        changes = {
            "Warehouse menus render cleanly after breaker repair, including after reloading the repaired save.",
            "The two oily warehouse puddles are separate, persistent mop tasks alongside the three floor-cleaning stages.",
            "Barn movement and Grandpa/exit actions use clearer contextual controls on desktop and mobile.",
            "Android 111 keeps multiplayer protocol 75 and is compatible with Android 109 and 110.",
        },
    },
    {
        version = "0.1.0-android.110",
        date = "Nov 12, 2026",
        title = "Warehouse restoration menu rendering fix",
        changes = {
            "Warehouse menus now render cleanly after repairing the breaker, including when reopening the computer.",
            "Graphics clipping, stencil, shader, blend, and camera transform state resets at the start of each frame.",
            "Android 110 keeps multiplayer protocol 75 and is compatible with Android 109.",
        },
    },
    {
        version = "0.1.0-android.107",
        date = "Nov 11, 2026",
        title = "Story mode startup fix",
        changes = {
            "Fixed the Android story opening crash by including its bike artwork in the game package.",
            "Android package smoke tests now enter story mode and render its packing and travel scenes.",
            "Android 107 keeps multiplayer protocol 75 and remains compatible with Android 106.",
        },
    },
    {
        version = "0.1.0-android.106",
        date = "Nov 11, 2026",
        title = "Story opening and shop restoration playtest",
        changes = {
            "Story start now travels from Millhaven to Grandpa's farm and hands control to the player after the conversation.",
            "The closed Picture Shop has five visual restoration stages, utility and breaker work, cleanup, and a grand-opening goal.",
            "The ride HUD and GPS have clearer spacing and a compact layout for narrow screens.",
            "Receipts, delivery signatures, estimate layouts, cutter menu navigation, and mobile text entry received updates.",
            "Park and campground paths, terrain lighting, sound playback, and selected character dialogue have new playtest work.",
            "PC 106 and Android 106 share multiplayer protocol 75. Update every participant before joining together.",
            "The new-shop multiplayer lobby, synchronized story opening, and grand-opening scene are still in development.",
        },
    },
    {
        version = "0.1.0-android.105",
        date = "Nov 10, 2026",
        title = "Readable interfaces and connected delivery routes",
        changes = {
            "Courier Prime typewriter text, clearer HUD balances, larger mobile office pages, and scrollable job details improve readability.",
            "Player and employee trucks carry multiple completed jobs, with delivery stops and navigation for mixed destinations.",
            "Customer pickup trucks appear on town roads; stalled traffic can recover and resume its deliveries.",
            "Improved town roads, recreation areas, GPS directions, and a loading-dock exterior connect warehouse work with travel.",
            "Tutorial lessons and saved notices explain gameplay; the office browser and receipt archive keep information accessible.",
            "Customer replies and receiving schedules respect business hours while owners can continue production.",
            "PC 105 and Android 105 share multiplayer protocol 74. Update every participant before joining together.",
        },
    },
    {
        version = "0.1.0-android.104",
        date = "Nov 9, 2026",
        title = "Gameplay and delivery reliability",
        changes = {
            "Delivery jobs now guide loading, travel, docking, unloading, and completion through a clearer sequence.",
            "Shop work orders support repeat jobs with clearer quote and pickup handling.",
            "Machine maintenance and shared multiplayer controls validate state transitions more consistently.",
            "PC and Android gameplay acceptance now covers recovery paths, scene exits, and cross-device play.",
        },
    },
    {
        version = "0.1.0-android.103",
        date = "Nov 8, 2026",
        title = "Separate vehicle and world actions",
        changes = {
            "Vehicle mount and dismount controls are separate from doors, pumps, and other world actions.",
            "Mobile shows independent vehicle and ACTION buttons together when both actions are available.",
            "Touch layouts can be adjusted per view, with improved framing on wide phones.",
            "Options now includes update notes alongside the playtest diagnostics panel.",
        },
    },
    {
        version = "0.1.0-android.102",
        date = "Nov 8, 2026",
        title = "Grocery and commute update",
        changes = {
            "Push a directional shopping cart through grocery aisles, collect stocked items, and take the cart to checkout.",
            "Shopping and checkout screens show product artwork for items you can buy, including boxed cereal.",
            "The store's cat attendant now works behind the checkout counter.",
            "Kei truck rotation frames keep a consistent size.",
            "Delivery trucks brake more firmly with better road grip, especially the kei truck.",
        },
    },
    {
        version = "0.1.0-android.101",
        date = "Nov 7, 2026",
        title = "Persistent employee and NPC commutes",
        changes = {
            "NPCs and employees can make persistent commute journeys between locations.",
        },
    },
}
