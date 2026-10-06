# NPC Worker Hiring and Machine Operation Plan

**Status:** The cat hiring/cutter pilot, ordered cutter schedules, shift continuation and employee labor accounting are playable. Press, wrapping, transport and the broader policies below remain planned. **Date:** October 6, 2026.

See [current implementation and verification](npc_worker_build_status.md) for the exact implemented scope. Open **HIRING** from the office computer's address-bar dropdown to hire and pay workers; **SCHEDULE** queues up to 16 accepted cutter jobs per employee with automatic progression, pause/resume and completion history. Every pallet in a job is cut before moving to the next job. Stock still needs player staging and clear cutter output.

Players can hire critter employees to cut, print, and eventually finish and move work around the shop. Applicants visit reception, show a resume, email it through CritterNet, and negotiate pay and working days in the computer inbox. Hired workers arrive for their agreed shifts, operate real machines on real job pallets, earn hourly wages, and take breaks to recover tiredness and focus.

Start with a cat worker based on Radio Cat from Mouse Frontier. The first playable stage should complete the whole hiring and payroll loop with one cutter operator. The subsequent stages add the Heidelberg Windmill, finishing, and pallet transport. Each stage includes the animations for the actions it makes playable.

All behavior, resumes, and correspondence belong to the game's simulation. The host advances them on the shop calendar, including while the player reads the computer.

## The hiring experience

1. An applicant enters through the front door and waits at reception. Interacting opens a short resume preview with experience, machine skills, availability, and requested wage.
2. The player chooses **Request emailed resume** or **Decline application**. Requesting an email creates one application record; repeated interactions cannot create duplicates.
3. After a short game-time delay, the computer receives an application thread with a clickable **Resume** attachment. The attachment is an in-game document generated from the applicant's stored profile.
4. The player sends an offer containing hourly pay, working days, shift times, role, start date, break terms, and overtime permission. A cost preview shows daily and weekly payroll.
5. The applicant accepts, counters with revised terms, or declines. The player can counter, accept the latest terms, or close the application. Every reply stays in the same thread.
6. Accepting the final agreement creates a signed contract and a Staff entry. Neither opening a resume nor sending an unaccepted offer hires anyone.
7. On the first scheduled day, the employee enters, clocks in, receives an assignment, performs the work, takes any scheduled breaks, and clocks out before leaving.

An application can move through `visiting`, `resume_requested`, `resume_received`, `negotiating`, and `offer_accepted`, ending in `hired`, `declined`, `withdrawn`, or `expired`. Store deadlines and processed event IDs so reopening the inbox or loading a save cannot repeat a reply or create a second contract.

### Applicant profiles and resumes

Each applicant has a stable identity and separate ratings for cutter operation, press operation, finishing, and logistics. Species determines the artwork; it does not determine competence. Show experience, skill bands, punctuality, attention to detail, available days and times, desired hours, and expected pay on the resume. Use readable bands such as Beginner, Competent, and Experienced, with exact values available in the employee detail view.

Keep the first cat broadly useful: a competent cutter operator and a junior press operator. Proposed starting ratings are cutter **65/100**, press **45/100**, attention **75/100**, and reliability **90/100**, with a requested wage around **$22/hour**. These are tuning values, not fixed requirements for every future cat applicant. Junior press work initially requires the player's proof approval.

Limit reception to one active applicant visit. Give ordinary customer, vendor, technician, and construction visits their existing places in the entrance queue. The first applicant appears during the next daytime recruitment window; later applicants arrive roughly every three to five game business days while hiring is enabled. Keep at most three open applications in the pilot, and let the player pause recruitment.

### Email negotiation

Use structured offers within the email thread. The player edits terms with controls and sends them as a message. The applicant evaluates the whole package: pay, requested hours, availability, role difficulty, breaks, and overtime. A modestly lower wage can be acceptable with preferred days or fewer hours, but an unavailable weekday cannot be bought by repeatedly resending the same offer.

Store each applicant's acceptable wage range and preferences when the application is created. A counteroffer retains the same preferences across saves. Allow up to three counters by the player before the applicant makes a final offer; identical offers do not consume a round or reroll the answer. The latest offer supersedes earlier offers, and stale accept buttons are rejected.

Proposed delays are 0.5 to 2 game hours for a resume or reply and three game days before an unanswered offer expires. The agreement starts at the next accepted shift after signing. Contract changes use a new email negotiation, apply from an agreed future date, and preserve all wages already earned.

## Contracts and hourly payroll

A signed contract records the employee, role, permitted machines, wage in cents per hour, weekdays, start and end time, effective date, paid rest breaks, meal break, overtime permission, and contract revision. The initial schedule editor supports same-day shifts of four to ten hours inside the applicant's availability. Overnight shifts can follow after the ordinary scheduling loop works.

### Wage starting points

The current national benchmark is the BLS May 2025 wage survey. Printing press operators have an hourly mean of **$22.77** and median of **$22.01**; print binding and finishing workers have a mean of **$21.38** and median of **$20.33**. Finishing is a reasonable comparison for the cutter role, rather than an exact wage survey of Polar operators. [BLS national occupational wage table](https://www.bls.gov/news.release/ocwage.t01.htm).

Use those benchmarks to center these proposed game bands. The skill bands and ranges below are balancing assumptions.

| Worker level | Initial hourly range | Expected behavior |
| --- | ---: | --- |
| Trainee | $16 to $19 | Slower setup, frequent checks, limited complex work |
| Competent operator | $20 to $24 | Ordinary jobs with occasional assistance |
| Experienced operator | $25 to $29 | Faster setup, fewer corrections, more complex work |
| Specialist | $30 to $35 | Advanced jobs and cross-training after those systems exist |

Negotiated wages remain fixed until a new agreement takes effect. Higher pay improves offer acceptance and retention; it does not instantly increase skill.

### Shift and payment rules

- An early employee waits until the scheduled start. A late arrival clocks in when physically present on the work floor. Walking between tasks, setup, cleanup, waiting for stock, and paid breaks count as paid time. Time before clock-in, after clock-out, and an unpaid meal does not.
- For an eight-hour shift, start with two paid 15-minute rest breaks and one unpaid 30-minute meal. Shorter shifts receive the applicable rest break. These are explicit game contract rules.
- Planned overtime is off by default. The game policy pays 1.5 times the agreed rate after 40 paid hours in a Monday-to-Sunday game week. A safe shutdown that crosses shift end is still paid, even when planned overtime is disabled.
- Pay the previous Monday-to-Sunday period on the following Monday at 09:00 game time. Show the exact payday and amount due in Staff. Signing authorizes automatic payment when due; the player can also settle earned wages early.
- Accrue exact paid time and retain fractional cents until settlement. Round the employee's payable total once, rather than rounding every frame. Partial payment reduces the balance without erasing unpaid earnings.
- If cash is insufficient, retain a payroll debt and send one overdue notice. The worker finishes a safe machine step, releases the machine, and stops starting work until wages are paid. After seven game days overdue, they can resign; resignation or dismissal never cancels owed wages.
- Payroll and NPC work stop whenever the authoritative shop simulation stops. There is no real-clock payroll or production while the game is closed.

**Example:** A $22/hour employee working Monday, Wednesday, and Friday from 09:00 to 17:00 earns 7.5 paid hours per day after the unpaid meal: **$165 per day and $495 per week**, before any overtime. Paid rest time is included in those 7.5 hours. The existing calendar makes a day last 300 real seconds, so an eight-hour shift lasts 100 real seconds. Wages therefore use game hours, the same basis already used by Windmill production.

The press quote includes a $22.77/hour estimated labor allowance plus machine overhead in `src/press_economics.lua`. The implemented cutter budget in `src/employee_labor.lua` accounts for employed workers' wages, skill, contract-paid rests and overtime. New recommendations increase only when the cutting charge falls below the staff-cost and margin floor. Existing press allowances stay separate; accepted/submitted quotes and promised promotions keep their agreed prices. Actual payroll is allocated to job work or idle/break/shop labor and shown in Job details and Payroll. Bills includes due wages and settles the same payroll ledger, so the quote allowance never becomes a second cash debit.

## Skill and worker condition

Track **tiredness** from 0 rested to 100 exhausted and **focus** from 0 distracted to 100 focused. Keep attention and reliability as longer-term profile traits. Add morale only when pay and working conditions have meaningful effects; the first stage can use explicit overdue-pay and resignation states without another meter.

Skill affects setup time, correction frequency, supported job difficulty, and choice of a safe production speed. Focus and tiredness modify those effects. They do not grant permission to ignore guards, proof approval, drying, machine condition, or stock limits.

Proposed initial condition rates, measured per game hour, are +8 tiredness and -6 focus during machine work; seated breakroom rest gives -40 tiredness and +32 focus; a designated ordinary rest point gives half that recovery. Off-shift recovery advances with simulated calendar time. Clamp every meter to 0 to 100. Waiting and walking need separate, gentler rates so a stock shortage does not exhaust an employee as quickly as continuous production.

At tiredness 70 or focus below 40, request an additional rest break after the current safe step. At tiredness 90 or focus below 20, stop beginning machine work until recovery. A sample effective-skill formula is:

```text
effective skill = clamp(machine skill
    - 0.30 * max(0, tiredness - 45)
    - 0.25 * max(0, 70 - focus), 0, 100)
```

Treat this formula and the rates as initial balancing controls. Begin with work duration varying roughly from 1.35 times the experienced baseline for a trainee to 0.90 times for an expert; never exceed the machine's physical speed limits. Slower setup and additional checking should carry most of the cost of low skill. Any setup errors use the existing cut and print quality rules, rather than an independent roll that silently destroys completed pallets.

Quality decisions are made once per setup or work stage using a stored seed and outcome. Saving, retries, or different frame rates cannot reroll them. A worker corrects a recoverable setup mistake, tests again, and requests help after two unsuccessful correction attempts. Junior press operators stop at proof review; qualified operators can approve an eligible proof when the contract and assignment permit it. The existing minimum proof score of 82 percent still applies.

Successful supervised and independent work gradually improves the relevant machine skill. Failed retries do not grant practice rewards; training progress belongs to the employee record. Teaching and specialist progression follow the first production stage.

### Breakroom use

Only a completed breakroom supplies its improved recovery. Register the current rest point as one usable seat in each completed bay, then add further seats only when the chair positions and occlusion are defined. Human sit interactions and NPC breaks must share seat occupancy so two characters cannot occupy one chair.

The worker stops safely, walks to an available seat, sits, rests, stands, and returns to the assignment. A full or inaccessible breakroom causes a wait or a break at the designated fallback point. Employees can still be hired without a breakroom; the room improves recovery and productive time. Recovery begins when the worker reaches the rest point, not when they merely choose a break.

## Autonomous machine work

The implemented cutter pilot supports one pallet through **HIRING > Staff**, or an ordered list of accepted jobs and installed cutters through **SCHEDULE**. The worker completes all pallets in the current queued job before advancing. A job's **Assign worker** shortcut and queues for additional machine roles remain planned. The employee does not accept customer estimates, purchase stock, or alter promised specifications.

Resolve every assignment to an exact machine ID, job ID, and pallet ID. Reserve both the machine and the eligible work pallet. Verify skill, shift time, availability of stock and supplies, machine condition, output clearance, and a walkable operator position before starting.

An employee follows `arriving`, `waiting_for_shift`, `clocked_in`, `walking_to_task`, `setting_up`, `working`, `checking`, `unloading`, `blocked`, `walking_to_break`, `resting`, `returning`, and `leaving` states. The current state drives the visible pose. Machine actions advance only through the normal domain controls, with operation IDs that prevent repeated cuts, material consumption, or outputs.

### Cutter operation

Walk to the selected cutter and load the selected eligible pallet. Read and verify its cut program, load a lift, set the gauge, position and rotate the paper, clamp, clear the guard, perform the guarded cut, inspect, and repeat the program and remaining lifts. Unload the actual finished pallet into a validated output space.

The NPC adapter must support the same dual-control and safety conditions as ordinary cutter operation. It must not toggle the multiplayer convenience control mode to gain permission. No worker walks away during a blade cycle or releases a cutter that is still unsafe. A blocked output retains the existing pallet and work progress.

### Heidelberg Windmill operation

Load an eligible pallet whose cut dimensions and plate status match the job. Perform the existing six setup tasks: **chase, packing, rollers, ink, feeder, and register**. Take a proof, verify it against the client artwork, obtain the required approval, choose a permitted speed, and supervise production.

Observe feed errors, stock shortages, machine condition, and the existing spoilage calculation. Use the normal good-copy and overage accounting. Complete cleanup with the required wash supply, unload to a clear point, and honor drying between colors. A shift ending during production stops the feeder and impression safely and retains an approved, resumable pass; it does not require finishing the entire job before going home.

### Finishing and transport

After cutter and press work are stable, add wrapper operation using the existing film, pallet, cycle, and output rules. Pallet transport then lets the worker fetch, stage, and return the same physical pallet with the pallet jack. Validate every pickup, carried-load route, and final drop against the fine placement grid and exact footprints. Forklift, upper-rack, and stacked-pallet work require a further qualification and animation stage.

In the first cutter and press stages, the player stages input pallets within machine reach and leaves output space. Clearly show **Needs input pallet**, **No output space**, **Waiting for plate**, **Drying**, **Machine unavailable**, **Needs proof approval**, or **Route blocked** when relevant. The eventual transport stage removes the need for ordinary manual staging; it never creates inventory through teleporting pallets.

### Access and player handover

Use the current fine placement geometry and walkmask. Derive approach points and hand targets from each machine's position and eight-way rotation. Provide alternative valid standing points around the operator side where the artwork supports them, so a nearby pallet does not unnecessarily prevent work. If none is reachable, highlight the obstruction and retain the assignment.

Reuse the collision-aware construction routing pattern, with bounded searches, movement substeps, and replanning when stock or equipment moves. Worker gait advances from actual movement after collision checks. Workers wait or yield to other people and vehicles; they do not walk through close-set pallets or occupied doorways.

**Take over** asks the NPC to reach a safe checkpoint and release the machine. Emergency stop remains immediately available to an authorized nearby player. Reassignment, rest, overdue payroll, dismissal, and shift end use the same safe release path. A worker beginning no new task near shift end still gets paid for the remaining agreed on-site time.

## Computer and mobile controls

The implemented computer dropdown has **HIRING** for applicants, staff and payroll, plus **SCHEDULE** for ordered cutter jobs. The broader views and actions below remain planned where not listed in the implementation report.

| View | Information and actions |
| --- | --- |
| Applicants | Resume, application status, latest terms, Open email thread, Decline |
| Negotiation thread in Inbox | Resume attachment, complete offer history, editable counteroffer, Accept terms, Send, Close application |
| Employees | On-shift status, assigned machine and job, skill, tiredness, focus, blocked reason, Assign work, Request break, Take over |
| Schedule and contract | Agreed days and times, start date, hourly rate, overtime, daily and weekly cost, Request contract change, End employment |
| Payroll | Paid hours, overtime, job labor allocation, idle and break time, accrued amount, next payday, payment history, outstanding balance |

Use separate details and offer screens on phones rather than squeezing the roster, contract, and email into one table. Support touch, mouse, keyboard, and controller through the existing UI projection and intent paths. Read-only resume previews and offer edits do not pause the simulation. Show updated wages and any expired offer when the player returns to a stale screen.

An employee's in-world interaction opens current task, condition, and help details. Keep persistent meters in Staff and concise status above a worker only when selected or needing attention.

## Cat worker identity and animations

Preserve Radio Cat's charcoal fur, amber eyes, pink inner ears and nose, rounded head, tail, brown workwear, olive scarf, and one-sided shoulder satchel. The reference is [Radio Cat identity](../references/characters/cat-worker/radio-cat-reference.png), copied unchanged from Mouse Frontier's `assets/sprites/NPCS/radio-cat.png`. The existing reference shows no headphones; do not add them merely because the character is called Radio Cat.

Mouse Frontier also has eight separately authored walk strips and matching two-frame idles in `output/character-motion/radio-cat/runtime`, with its spec at `character-motion/radio-cat.json`. Its recorded audit has zero errors and zero warnings. These are candidates for reuse, subject to review at Picture Shop scale; the audit does not prove new machine actions are ready.

Keep the applicant's original outfit for the first direction study. For machine operation, propose tucking the scarf and parking the satchel at a registered locker or rest position so both paws can handle paper. Approve that work outfit before producing its strips. Changing outfits requires matching idles, walks, and transitions; a visible satchel cannot disappear halfway through a walk. A carried paper stack is a separate prop tied to the relevant pose.

The scarf knot and satchel are asymmetric, so author or preserve all **eight** views: north, northeast, east, southeast, south, southwest, west, northwest. Do not make west by mirroring east. Machine action coverage follows the operator's facing derived from all eight machine rotations. A pose can be shared only when its physical hand and control relationships match.

### Required animation groups

Frame counts below are production targets per direction, before review. Locomotion uses distance timing; action and rest loops use game-state timing. One-shot actions finish or hold their final frame rather than looping backward.

| Group | Required poses or actions | Target frames and direction coverage | First used |
| --- | --- | --- | --- |
| Applicant and worker locomotion | Directional idle and complete walk, matching the current outfit | 2 idle and 8 walk frames in each of 8 directions | Hiring and cutter stage |
| Reception | Wait, greet, show resume, lower resume | 2-frame wait; 4 to 6 frames for each gesture in supported counter-facing views | Hiring stage |
| Shift transitions | Stow and retrieve satchel, prepare and restore work outfit | 4 to 6 frames at the registered storage-facing views | Cutter stage |
| Paper handling | Pick up, hold, carry, place, square and rotate a lift | 4 to 6 action frames; 8 carry-walk and 2 carry-idle frames per movement direction | Cutter stage |
| Cutter setup | Read job sheet, inspect stack, reach console, set gauge | 4 to 6 frames per operator-facing view | Cutter stage |
| Cutter cycle | Position lift, operate clamp, dual-button guarded cut, watch cycle, inspect result, unload | 4 to 8 frames per operator-facing view; hands clear of the cutting zone during the cycle | Cutter stage |
| Breakroom | Sit down, seated idle, recover or stretch, stand up | 4 to 6 transition frames and 2 to 4 rest frames per registered seating view | Cutter stage |
| Windmill setup | Mount and secure chase, set packing, adjust rollers, apply ink, prepare feeder, adjust register | A distinct 6 to 8 frame action for each task and operator-facing view | Press stage |
| Windmill proof and production | Take proof, inspect proof, start controls, attend feeder, watch delivery, stop controls | 4 to 8 frames per relevant station view | Press stage |
| Windmill completion | Remove output stack, clean rollers, wash up, unload | 6 to 8 frames per relevant station view | Press stage |
| Wrapper | Position pallet, attach film, start controls, observe cycle, cut and secure film, inspect | 4 to 8 frames per operator-facing view | Finishing stage |
| Pallet jack | Grip and release handle, pump and lower, empty push, loaded push, turn and stop | 4 to 6 action frames; 8 push frames in every movement direction | Transport stage |
| Forklift and upper storage | Mount, seated idle and drive, operate lift, dismount | Separate vehicle and driver layers after qualification and seat geometry are defined | Later transport stage |

Each machine work action has a stable foot anchor, hand target, paper or tool anchor, facing, depth order, and entry and exit pose. Render paws, paper, controls, furniture, and machine foreground in the correct order. The worker's work clock follows actual machine phases, including pauses. A frame depicting a cut or transfer does not itself mutate the job.

Keep the same visible body scale across walking, seated, and working actions. Use the Picture Shop reference height of 256 source pixels at the existing world draw scale; the tail and satchel do not determine body height. The proposed NPC pace starts at 72 world pixels per second and 13 world pixels per gait frame, matching the established visitor scale. Skill primarily changes work pace, not a character's proportions or walk cadence.

Every walk and carry/push loop uses these eight phases in order: left contact, left weight-down, right passing, right knee-up, right contact, right weight-down, left passing, left knee-up. Retain the last direction when stopping; all gait frames advance only from movement actually achieved. Initial speed and acceleration profiles use the established small variations around a mean of 1.0.

The current generic character direction selector mirrors westward views. The cat needs a selector driven by its explicit direction map, with carry and push recognized as distance-driven locomotion. Retain the rabbit's existing mirroring choices. Applicant and work outfits each need their own matching movement set; texture caching must also handle both outfits appearing in the shop at once.

### Art production and mobile memory

`character-motion/cat-worker.json` now registers the pilot's 26 reviewed runtime strips: eight idle views, eight walk views, eight cutter operator views and two seated break views. Its remaining action groups describe future roles. Immutable locomotion masters and generated action sheets, prompts and hashes are in `assets/source/cat-worker-v1/`; reviewed 256px runtime strips are in `assets/generated/characters/cat-worker/`. Rebuild with `tools/build_cat_worker_assets.py`, then audit and review the generated strips before promotion.

Target 256 by 256 runtime cells for the new cat while retaining the current 512-cell contract for existing characters. This requires a deliberate per-character frame-size extension to `character_assets.lua`, the quad builder, anchors, metrics, and preparation tools. Check clarity at actual world size before accepting that reduction.

At 512 cells, eight-direction walk and idle textures alone require **80 MiB** decoded: 64 walk frames plus 16 idle frames at 1 MiB each. At 256 cells they require **20 MiB**. Numerous machine strips would quickly exceed a phone's budget if all remained loaded. Add a bounded cache for action textures, share textures across employees of the same species and outfit, retain the active and immediate transition poses, and release unused work actions. Start with a 32 MiB incremental cat-texture target at 256 cells, and measure the full scene before raising the worker count.

Produce and review in this order: reference and work outfit; eight direction studies and idles; walks; resume and shift gestures; paper handling and cutter actions; rest; press; finishing; transport. Review labeled contact sheets, loops at normal speed and half speed, alpha against contrasting backgrounds, and all directions together. Then verify hand reach and occlusion against every installed machine rotation, close pallet placement, both breakroom orientations, and desktop and phone world scale. A generic machine-use loop does not complete the machine animation requirements.

## Integration with the current game

| Current component | Planned responsibility |
| --- | --- |
| `business_calendar.lua` and `config.lua` | Absolute game-hour deadlines, shift boundaries, payroll periods, configurable wage and condition tuning |
| `inbox.lua`, `job_service.lua`, `computer_screen.lua` | Application threads and resume references, offer controls, Staff views; retain existing customer and service emails |
| `world.lua`, `customer.lua`, `warehouse_construction.lua`, `navigation.lua` | Dedicated applicant and employee actors, reception access, collision-aware routes, break and work targets |
| `machine.lua`, `windmill.lua`, `wrapper.lua`, `machine_fleet.lua`, `pallet_state.lua` | Exact unit and pallet operations, safe work adapters, supplies and output checks |
| `workshop_authority.lua`, `office_authority.lua`, `office_intent.lua`, `net/session.lua`, `net/protocol.lua` | Shared machine ownership, typed hiring and payroll actions, host simulation, bounded worker replication |
| `warehouse_layout.lua`, `warehouse_breakroom_presentation.lua`, `world_renderer.lua` | Registered seats, shared occupancy, employee depth and furniture occlusion |
| `character_assets.lua`, `character_animation.lua`, `character_anchors.lua`, `character_metrics.lua`, `gait_motion.lua` | Explicit eight-direction selection, distance-driven gait, variable frame size, action caching and anchors |
| `state.lua`, `save_schema.lua`, `save.lua` | Durable applicants, contracts, skills, condition, earned wages, assignments, and safe task recovery |

New modules should separate `employees.lua` for profiles and hiring, `employment_contracts.lua` for immutable agreements and revisions, `payroll.lua` for time and payments, `employee_ai.lua` for routes and decisions, and `employee_work.lua` for cutter, press, and wrapper adapters. Add an employee inbox adapter so existing notice/archive code retains thread, resume, offer, and contract IDs instead of dropping them. UI code displays these records; it does not own the simulation.

### Machine ownership and multiplayer

Current workshop authority accepts human player IDs 1 to 4. Give employees stable IDs such as `EMP-0001` in a separate actor namespace. Do not represent them as player 5 or let a guest manufacture an employee command.

Introduce a shared reservation owner that can be a human or employee. Human console leases and host-only NPC claims compete for the same physical machine; claiming an assigned unit also claims its pallet. A machine already in human use remains unavailable to an NPC. Refactor command validation so both actors reach the same safety and stock rules while retaining the existing checks on network players. Inspection never grants control.

The shop owner manages hiring, contracts, dismissal, and payroll. Connected players can inspect workers and perform allowed machine handovers. The host alone creates applicants, decides negotiation outcomes, advances needs and payroll, and performs NPC machine commands. Replicate bounded employee poses and semantic action phases for drawing; send durable profile, contract, and ledger changes through shop state updates. Keep resumes as typed data rather than binary attachments in network packets.

### Saved state and time boundaries

Persist the employee ID, profile and experience, application and email references, complete contract revision history, active contract, exact paid-time checkpoint, payroll balance and settlement IDs, skill progress, tiredness, focus, assignment IDs, safe task step, and any predetermined quality outcome. Rebuild paths and transient machine claims when loading. Only reacquire a unit after validating its saved state and all competing owners; otherwise hold the assignment for review.

Process shift, break, offer, and payroll boundaries chronologically when a frame crosses several deadlines. Split machine and payroll updates at those boundaries so one large update cannot grant a full frame of work after clock-out or miss a payday. Use durable operation IDs for contract signing, work stages, wage accrual checkpoints, replies, and payments.

The implemented cutter/schedule pilot uses save schema 20, employment v4 and network protocol 25. Radio Cat, Tinker Fox and Ferret Engineer use reviewed Mouse Frontier movement sprites. Signed terms allow four-to-twelve-hour daytime/overnight shifts and one-to-four-week pay cycles. New saves choose five-to-sixty-minute days; older saves retain their five-minute pace. Version 19 terms gain weekly pay without rewriting existing wage debt or due dates. Earlier migrations preserve contracts, payroll, money, agreed prices, jobs, loans, placements and real production. Version 18 / employment v2 gains cumulative labor totals, with old tracked wages recorded as unallocated shop labor. Unfinished cutter work resumes on the next agreed shift, including across days off and save/reload. The Payroll shop budget covers whole shifts, bills, loans, cutter capacity and payday reserves. Additional roles and dedicated fox/ferret machine action sequences still require reviewed work. Save wiping remains a separate, explicitly agreed testing choice.

## Implementation order and completion checks

| Stage | Deliverable | Completion check |
| --- | --- | --- |
| 1 | Hiring and financial rules with neutral UI fixtures | Resume request, counters, final agreement, schedules, and exact wages persist without duplicates |
| 2 | Cat cutter operator and useful breakroom | Visible applicant-to-employee journey; cat completes an actual multi-lift cutting job, rests, leaves safely, and receives correct pay |
| 3 | Cat press operator | All six setup tasks, proof supervision, production, drying between colors, cleanup, and resumable shift end on exact machine units |
| 4 | Finishing and pallet transport | Wrapper and pallet jack operate on canonical pallets with safe reservations, clear routes, and validated placement |
| 5 | Larger workforce and training | Several employees share machines, seats, paths, and payroll without duplicate work, visual drift, or phone memory failures |

The first playable release combines stages 1 and 2. It must include hiring, an actual contract, hourly cost, a real cutting result, conditions, usable breaks, save recovery, and the corresponding cat animations. A Staff menu with an invisible job-completion timer does not satisfy that release.

Required verification covers offer revision conflicts and expiry; exact cents and partial payments; paid and unpaid breaks; overtime and midnight boundaries; late arrival versus a blocked entrance; consecutive shifts; low cash; dismissal with wages owed; save/reload during every safe machine step; low skill and proof retry limits; stock and output shortages; close pallets and moved machines; each of eight machine orientations; competition with human operators; guest attempts to change contracts; and shared breakroom seats in both bays.

For art, require matching idle in every direction, retained facing when stopped, correct gait phases, no movement animation while fully blocked, stable scale and foot anchors, distinct machine work poses, correct hand reach and occlusion, transparent frames, and measured texture residency. Phone UI and visual review are part of completion even though APK packaging is outside the current planning work.
