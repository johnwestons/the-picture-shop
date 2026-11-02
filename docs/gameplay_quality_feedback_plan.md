# Gameplay quality and player-feedback plan

## Goal and scope

Make the existing print-shop loop easier to read and more satisfying by showing production progress, catching quality problems before delivery, letting customers react to the work, supporting employee coordination, and giving the player a useful end-of-shift recap.

Keep the playable equipment to the Polar paper cutter, Heidelberg Windmill printer, skid wrapper, and the shop's existing handling equipment. Use the jobs and production steps already in the game. This plan does not include customer personality systems or new job/product variants; those ideas are intentionally deferred.

## Design rules

- Every warning or consequence should point to a visible cause in the job record or production history.
- Let the player fix a problem before it becomes a customer-facing failure whenever the job is still in the shop.
- Only count defects that reach the customer against quality and reviews. Internal spoilage that is caught and replaced should affect waste and cost, not the customer's rating.
- Make routine production status visible without forcing the player to open every job or read repeated dialogue.
- Keep phone, email, desktop, and touch controls usable on mobile as well as desktop.

## Phase 1: Give each job a production and outcome record

Before adding more feedback screens, create one source of truth for what happened to each job. Record stage changes and their in-game timestamps: accepted, materials ready, cutting, printing, wrapping, quality hold, ready to ship, shipped, and closed. Store counts for good sheets, caught defects, rework, scrap, and the quantity actually delivered. Record any delay reason and any customer-resolution action.

Use existing job state and reputation/review systems where possible. Add defaults when loading older saves so existing progress remains readable. Keep the history compact: retain milestone and incident events rather than logging every simulated machine tick.

**Ready when:** a job's current stage and major reasons for delay, waste, rework, and customer outcome can all be derived from its saved record after loading an older or newer save.

## Phase 2: Add a pre-delivery quality check

Add a short inspection step once a job has completed its existing production and before it is dispatched. Show the player what to check, using only quality dimensions the game already simulates or can explain: cut accuracy, print quality/registration, finished quantity, and visible handling damage. Begin with a small sample from each pallet or job rather than asking the player to inspect every sheet.

The check should use the job's actual production results and recorded errors, not an unexplained random roll. A clear pass releases the job for shipping. A failed check names the issue and offers the appropriate existing-machine rework path. Rework consumes time and materials; replacing a caught defect before shipment avoids a customer complaint and rating loss, while still appearing in the shift's waste/rework figures.

**First release:** one checklist, one sample interaction, pass/hold result, and an explicit rework or release choice. Later, employee quality skill can help detect issues, but the player must always be able to understand the result.

**Ready when:** an on-spec job can ship without an unnecessary inspection loop; a known defect is caught, can be reworked with existing machines, and does not lower customer satisfaction if the corrected job is delivered.

## Phase 3: Add customer calls, emails, and resolution choices

Create a customer case only when a meaningful problem reaches the customer or threatens a committed delivery: late shipment, delivered off-spec work, missing quantity, or damage. Use a call for an urgent case that needs a quick decision, and email for a lower-urgency explanation or a written record. One incident should not generate repeated calls and emails about the same problem.

Present concise facts: job, promised and current dates, affected quantity, known cause, and the cost or time of each response. Initial response choices can be:

- remake or replace the affected quantity;
- offer a partial refund or account credit;
- apologize and explain the corrective action, when no compensation is needed;
- decline responsibility, with a clear reputation risk.

Track the resolution and its cost. Feed the customer's final outcome into the existing rating/review path, so a well-handled mistake can recover some trust while an unresolved delivery failure has a visible cost. Preserve the existing rule that internal defects caught before shipment do not count as customer-facing failures.

**Ready when:** a qualifying incident creates one actionable case, the player can resolve it from the existing phone/email/computer flow, and the chosen outcome is reflected in job history, finances, and customer reviews.

## Phase 4: Show production progress and employee coordination

Add a compact progress view to the Job Desk and job detail. For each active job show its current stage, completed stages, quantity completed versus target where available, and the next blocker. Link the progress to the physical pallet and existing cutter, Windmill, wrapper, and shipping flows. Do not invent new work stages just to fill a progress bar; show a named waiting reason when a job cannot advance.

Have employees report useful, actionable events rather than generic chatter: setup complete, machine ready, stock needed, quality hold, blocked by another worker, or job ready for the next station. Show the alert once in the job feed and, when useful, with a brief speech bubble. Surface competing work or an unavailable machine as a clear blocker so the player can reassign staff or choose another available machine.

Keep alert frequency bounded: one notice per incident and no repeated alert while the state is unchanged. Let the player inspect the job or worker directly from the notice where the current UI supports navigation.

**Ready when:** a player can identify what every active job is doing and why it is waiting from one screen, and simultaneous employees working on separate machines or duplicate machines do not generate contradictory progress reports.

## Phase 5: Add an end-of-shift scorecard

At shift end, show a short recap sourced from the job records: jobs completed, on-time deliveries, first-pass quality, caught defects, rework and scrap, customer cases resolved or unresolved, and the resulting revenue/refunds. Include employee attendance or missed scheduled time only where the current schedule system already records it.

For each weak result, link to its cause (for example, a material wait or a quality hold) rather than presenting an unexplained grade. Let the player compare against the previous shift once the underlying event data is reliable. Keep bonuses and new progression systems out of the first version; establish the recap and its cause links first.

**Ready when:** the recap totals match the underlying jobs and transactions, explain the largest shortfall, and can be dismissed without blocking the next shift.

## Suggested implementation order

1. Add the compact job-event/outcome record and backward-compatible save defaults.
2. Build inspection, hold, and rework using current production quality and machine paths.
3. Add customer cases and response outcomes on top of the same job record.
4. Add progress and employee alerts using those recorded events.
5. Add the shift scorecard after the job and customer totals are stable.

This order keeps each layer grounded in the same job history and avoids building a progress bar, review, or score that disagrees with what happened on the floor.
