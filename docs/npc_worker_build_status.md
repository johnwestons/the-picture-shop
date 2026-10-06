# Cat workers: current implementation

October 6, 2026. The hiring and cutter operator pilot now includes ordered job schedules in the shared desktop/Android game. The broader [worker plan](npc_worker_hiring_plan.md) remains the roadmap for press, finishing and transport work.

## Using the feature

1. Open the office computer and use the arrow beside its address bar to choose **HIRING**.
2. Keep recruitment open. The first cat applicant visits reception on a weekday; request the emailed resume at reception or in **Applicants**. Later applicants are generated at three-to-five game-day intervals, with a single visible reception visitor and at most three open applications.
3. Open the resume attachment from **EMAIL**, or select the applicant in **HIRING**. Offer $10–$100/hour, selected weekdays and a four-to-ten-hour shift within 08:00–18:00. Wait for the reply; the applicant accepts or counters according to their stored wage requirements. A changed offer consumes a negotiation round; repeating identical terms does not. Accepted offers expire after three game days.
4. Sign the latest accepted offer. This creates a contract and staff record and starts on the next upcoming agreed shift. Up to three employees can be hired at once.
5. Choose **SCHEDULE** from the address-bar dropdown and select the employee. **ADD JOB** appends an accepted job and a specific installed cutter. Queue up to 16 jobs, reorder or remove pending work, and use pause/resume as needed. The worker cuts every pallet in the first job before automatically starting the next. The last 32 completed, removed or unavailable entries appear in history. **HIRING > Staff** still supports one manually assigned pallet; pause the queue first. Use the pallet jack to stage each pallet beside its cutter and clear the output. Workers walk to the machine, load lifts, select and execute the actual cuts, and unload completed stock. Hard and medium work require the appropriate skill. More skilled, focused workers take less time between operating steps.
6. In **Payroll**, review or pay earned wages. Waiting at the shop, walking and rest breaks are paid. Meal breaks are unpaid. Weekly wages come due Monday 09:00; pay after 40 paid hours in a week is 1.5×. Cash shortages make partial payments and retain the exact remaining debt. Dismissal does not erase earned wages. Overdue wages stop new work and seven game days of overdue debt can cause resignation.

Shift time follows the active shop calendar, including while reading the computer. Closing the game does not accrue offline work or payroll. Workers finish an already-running cutter cycle safely before leaving or pausing, and that finishing time is paid. Pause their schedule or assignment before taking over a reserved cutter, moving it or selling it. A loaded pallet stays with its job until finished or unloaded. Missing stock, blocked output, overdue wages or an unavailable machine stop the first job; they do not silently skip ahead. A canceled job is recorded as unavailable before advancing.

Two 15-minute paid rests are scheduled during an eight-hour shift. Shifts of six or more hours include a 30-minute unpaid meal. Extra rest is triggered by high fatigue or low focus. A completed breakroom with a free seat gives full recovery after the worker actually walks to it; standing rest gives half recovery. Reserved seats cannot also be occupied by a player. Applicant and worker movement follows the walk mask, equipment and other actors.

## Files and artwork

- Hiring UI: `src/screens/hiring_screen.lua`, embedded in `src/screens/computer_screen.lua`.
- Schedule UI and queue domain: `src/screens/schedule_screen.lua`, `src/employee_schedule.lua`; integration checks in `src/tests/employee_schedule_test.lua`.
- Domain and simulation: `src/employees.lua`, `src/employment_contracts.lua`, `src/payroll.lua`, `src/employee_ai.lua`, `src/employee_work.lua`.
- Artwork: `assets/generated/characters/cat-worker/` contains **26 transparent strips / 120 frames**: eight two-frame idles, eight eight-frame walks, eight four-pose operator strips, and east/west four-pose seated rests. All eight movement views are authored; the asymmetric satchel is never mirrored.
- Runtime registration: `src/config.lua`, `src/cat_worker_anchors.lua`, `src/cat_worker_metrics.lua`, `src/employee_renderer.lua`, `character-motion/cat-worker.json`.
- Sources: approved Radio Cat locomotion was copied intact from the Mouse Frontier project. New operator and break artwork was generated with built-in ImageGen. Immutable source sheets, exact prompts, rejected drafts and SHA-256 hashes are recorded in `assets/source/cat-worker-v1/source-manifest.json`.
- Rebuild/review: `tools/build_cat_worker_assets.py`, `tools/run_employee_preview.ps1`, `tools/employee_preview/main.lua`.

Walk timing uses achieved movement distance and the same eight gait phases, speed curve and acceleration curve in every direction. Blocked motion stops the gait and keeps the last direction. All actions use static body/foot anchors; seated poses retain the standing character's scale. Maximum loaded cat textures use 30 MiB; runtime anchor discovery scans no pixels.

## Saves and multiplayer

Save schema **18** stores applicants, signed contracts, assignments, ordered work queues, completion history, conditions and weekly wage ledgers. Version 17 employees migrate to empty queues while retaining their contracts, assignments and payroll. Version 16 saves migrate to an empty hiring system. Local loads stop active worker poses and release reservations before the next shift update; queues, contracts, earned wages and production stock remain durable. No real-world elapsed time is applied.

LAN protocol **23** uses typed, owner-only hiring/payroll/schedule actions and host-owned simulation. Guests can inspect hiring, staff and schedules. Stable task IDs and revision checks reject duplicate or stale queue edits; the same job cannot be assigned to two employees. Compact realtime NPC poses carry movement direction, gait phase and machine/break action alongside environment snapshots; profile, contract, queue and money updates stay in reliable shop state. NPC identifiers are separate from human player IDs. All participants need matching builds.

## Verification

- Desktop: **3,998 checks** pass, including the actual reception interaction, two-lift / four-trim cutter flow, automatic completion of a two-pallet job followed by a second job, stock-safe blocked output, safe pause/resume, queue order and history across reload, queue/history limits, skill requirements, duplicate/stale actions, typed resume attachments, owner permissions, partial wage debt, overtime and safe-cycle finishing pay, save migration, and bounded realtime poses.
- Art: the strict locomotion audit covers all 16 walk/idle strips with **zero errors and zero warnings** at the original 10px center tolerance. The raw 26-strip audit reports zero errors and eight silhouette-center warnings from reaching, sitting and rising. Those poses retain registered body anchors; the separate action review allows 24px silhouette movement (observed maximum 20.5px). Locomotion retains its stricter threshold.
- In-engine review: **26 desktop and phone landscape captures** cover the real reception route, resume, offer, working cutter, staff, assignment, payroll, email attachment, occupied breakroom, Schedule queue/add/history and the expanded computer dropdown. The actual scheduled cutter route, cut cycle and progression to the next job are asserted before capture. Review output is in `output/cat-worker-review/`.
- Last published installer, Android 36: **3,950 checks** pass against its packaged mobile game. It contains the original hiring/cutter pilot, all 26 cat strips, all 60 visitor strips and all 273 Lua files with matching source bytes. Android 37 is being built for Schedule support. Download details and checksums are in `ANDROID_PORT.md`. No phone was connected; remote installation and physical phone playtesting are not claimed.

## Remaining work

This pilot operates the cutter. Heidelberg press work, wrapping, autonomous pallet transport and their specialized animation sets are not implemented yet. Applicants currently negotiate pay and a valid schedule with fixed break/overtime rules; individual weekday preferences, richer qualifications, variable attendance, mistakes/proof approval and optional overtime negotiations remain planned. Applicants send typed inbox notices rather than a separate threaded mail UI. The original Radio Cat outfit remains in the pilot; a dedicated outfit change is not implemented.
