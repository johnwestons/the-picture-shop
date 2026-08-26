# Machine ownership, condition, and maintenance

`src/machine_fleet.lua` is the persistent machine contract. Every physical machine has a unique `MCH-####` ID,
serial, model ID, acquisition channel, installed/stored state, purchase price, cycles, operating time, component
variables, calculated condition, maintenance history, technician notices, and online delivery orders. Save format 13 validates and
migrates this data.

## Adding a machine model

1. Add one definition to `MachineFleet.definitions` and its ID to `MachineFleet.order`.
2. Give every serviceable component a stable ID, label, condition weight, wear-per-cycle value, and maintenance task.
3. Add the model's online and used-dealer starting conditions plus its full-condition base price.
4. Build its placement/render/interaction consumer. A first purchased unit can then be installed; additional units
   remain in storage until the installed unit is sold or a multi-placement consumer is added.
5. Call `MachineFleet.recordUse(state, modelId, cycles)` only when a real production cycle completes. The fleet
   module recalculates condition from that individual unit's component variables.
6. Call `MachineFleet.canOperate` before beginning work. A machine below 15 percent condition is unavailable until
   maintenance restores it.

Do not add a marketplace listing without a live world consumer unless it is explicitly marked as unavailable. This
keeps players from spending money on decorative or unreachable prototypes.

## Sales channels and valuation

The office computer **Online** tab uses `MachineFleet.offers("online")`. These machines begin in strong inspected
condition. `MachineFleet.orderOnline` reserves the next unique machine ID, deducts the price, and stores the unit
inside an `MDO-####` delivery rather than adding it to owned machines. The world scheduler assigns that order a
dedicated `machine_delivery` flatbed. `MachineFleet.unloadDelivery` is the only transition that moves the exact
reserved unit into the owned fleet, installing the first unit of a model and storing later duplicates.

The used-machinery salesperson uses `MachineFleet.offers("dealer")`; dealer condition is intentionally lower and
the condition-derived price is discounted. Dealer purchases remain direct handoffs. `MachineFleet.priceFor` and
`MachineFleet.resaleValue` keep condition meaningful for purchase and resale instead of treating it as descriptive
text.

## Machine-specific maintenance hubs

`src/machine_maintenance.lua` owns transient maintenance sessions, while each machine screen owns its maintenance
hub and launches that machine's individual minigames. The Polar 115 hub currently launches animated oiling and
blade-removal/sleeving work areas. Oiling consumes one delivered maintenance kit only after all moving lubrication
targets are completed. Blade service blocks production while the knife is out of the machine.

One-time and recurring weekly blade-technician appointments are persistent and appear on the calendar. A technician
can arrive normally, run one day late, or miss that week's visit. Late and missed visits create read-only service
messages in the office email inbox. Successful service sharpens and reinstalls a blade that the player secured in
its wooden sleeve.

Maintenance artwork should remain modular: a static machine panel, separate moving parts, separate tool/cursor
sprites, and explicit hit targets. This matches the existing cutter GUI's layered button, clamp, blade, paper, and
backgauge approach and avoids baking interactive state into one image.
