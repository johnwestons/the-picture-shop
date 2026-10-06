# Economy rebalance and machine credit

**Implemented:** September 25, 2026

**Currency and market basis:** U.S. dollars; U.S. supplier and equipment asking prices.
**Price source report:** [Real-world price benchmark](economy_price_benchmark_2026-09-24.md)

## Applied prices

Machine catalog prices now use the real-world used-equipment comparisons and stated condition. The online catalog represents a strong-condition used listing; the dealer listing represents a lower-condition used machine. The benchmark's new-equipment examples informed the capital scale, especially for the forklift. The game does not label its press, cutter, or wrapper offers as new machines.

| Item | Online / bulk | Dealer / retail | Basis |
|---|---:|---:|---|
| Polar 115 cutter | $12,740 | $9,391 | Public used listings around $9,000–$12,740; a smaller new hydraulic cutter is about $22,558. |
| Automatic skid wrapper | $22,500 | $15,609 | New semi-automatic comparisons are $7,400–$9,900; the offer is modeled toward higher-throughput automatic equipment. |
| Heidelberg Windmill | $5,640 | $4,110 | Strong used listings reach $6,000; this discontinued press has no new-production price. |
| House paper | $100 / 1,000 sheets | $30 / 250 sheets | Explicitly sized 25×38 in, 20 lb; sheet-area comparison with 20 lb letter paper. |
| Cover stock | $250 / 500 sheets | $60 / 100 sheets | Explicitly sized 23×35 in, 100 lb. |
| Black letterpress ink | $184 / four 2.2 lb cans | $46 / 2.2 lb can | Direct specialist-supplier match. |
| Spot-color ink | $168 / four 2.2 lb cans | $42 / 2.2 lb can | Uses the report's per-can allowance where a matching color SKU was unavailable. |
| Letterpress wash | $24 / twenty-four 4 oz cleanups | $8 / six 4 oz cleanups | Pack sizes are defined; anchored to a $32 per-gallon specialist wash. |
| Windmill tympan | $54 / 50 sheets | $11 / 10 sheets | Matches the $107.70 per 100-sheet reference, rounded to whole dollars. |
| Shipping cartons | $407 / 100 | $84 / 20 | Defined as 12×12×12 in, 275 lb test. |
| Stretch film | $205 / 12 rolls | $40 / 2 rolls | Defined as 20 in × 1,000 ft, 70 gauge. |
| Pallet shelving | $1,200 | — | Ten pallet positions at installed per-position estimates. |
| Employee breakroom | $8,300 | — | Midpoint of the cited $7,280–$9,386 8×10 modular-office examples. |
| Warehouse forklift | $33,000 | — | Midpoint of new 4,500–5,000 lb examples at $29,399–$36,599. |
| Press plate minimum / area | $12.50 / $0.55 per sq. in. | — | Concord Engraving's listed minimum and area rate. |
| Press labor allowance | $22.77 per hour | — | BLS May 2025 national mean for printing press operators. |

The report explains where comparisons are approximate, including the paper-area conversion, wrapper automation, machine condition, and shipping quantities. Floor work remains $2,500 because no square footage or installed scope is defined. Bundled plate materials, maintenance kits, and safety supplies retain their existing prices until their contents are specified well enough to compare against supplier items.

## Machine credit

The computer now has a **Credit** tab. It shows the player's score, tier, online and dealer machine offers, required down payment, APR, term, estimated monthly payment, open balances, and scheduled or overdue installments. The player reviews the offer and signs before an online machine order is placed or a used dealer machine is acquired. The host validates and records online financing for multiplayer play.

New accounts start at **560** on a 300–850 game scale. Financing is available from 500 points and is limited to three open machine loans. Terms are fixed for each new agreement based on the score at signing:

| Score | Game tier | APR | Down payment | Term |
|---:|---|---:|---:|---:|
| 740–850 | Excellent | 7.49% | 5% | 72 months |
| 680–739 | Good | 9.99% | 10% | 60 months |
| 620–679 | Fair | 12.49% | 15% | 48 months |
| 580–619 | Fair | 15.49% | 20% | 48 months |
| 500–579 | Poor | 18.99% | 25% | 36 months |

Payments use fixed-rate monthly amortization with monthly interest accrual. Signing records a small inquiry impact. The maturity installment settles the remaining balance, including rounding differences. A financed machine carries a lien and cannot be sold until the loan is paid. The player can pay an installment from the Credit tab once it is due.

Monthly shop invoices and equipment loans report late status at 30, 60, 90, and 120 days. A 5% late fee applies after 15 days, with a $10 minimum and $50 maximum. Timely shop bills and loan payments build score; late reports lower it, and a loan becomes defaulted at 120 days. These score changes are a transparent game model inspired by real payment-history weighting and delinquency severity; they are not a consumer credit score or a claim to reproduce a lender's underwriting system. See [CFPB guidance on credit scores](https://www.consumerfinance.gov/consumer-tools/credit-reports-and-scores/understand-your-credit-score/) and [myFICO's late-payment FAQ](https://www.myfico.com/credit-education/faq/negative-reasons/late-payments).

Credit records and loan schedules are saved with the shop. Existing version 15 saves migrate to a new starter profile at 560 with no loans, while existing money, inventory, and machine ownership remain intact.

## Employee costs and progression — October 6, 2026

**HIRING > Payroll > SHOP BUDGET** plans full-shift wages, weekly overtime, shop bills and active/defaulted machine-loan payments before estimating money left for growth. This includes paid idle time and rests, rather than counting only hands-on job time. The capacity estimate respects installed cutters and overlapping shifts. Standard cutting uses the existing $150-per-lift service charge; negotiated labor, paid-break/overtime burden, machine overhead and the 35% target gross margin can raise recommended new quotes when necessary. Accepted customer prices remain fixed.

For a Radio Cat at $22/hour, Monday–Friday 08:00–20:00, five unpaid half-hour meals leave 57.5 paid hours: 40 regular plus 17.5 overtime hours cost **$1,457.50/week**. Four-week pay terms require **$5,830** in wage reserves; they change when cash is paid, not the expense or profit. January's $1,650 monthly operating bill adds **$372.58/week**. At twenty completed, customer-supplied 500-sheet/four-trim lifts for $150 each, the planning allowance leaves:

| Real minutes per game day | Machine allowance per lift | Estimated weekly money for growth |
| ---: | ---: | ---: |
| 5 | $26.49 | $640.12 |
| 20 | $8.87 | $992.52 |
| 60 | $4.96 | $1,070.72 |

These use the game's operating-time model and reserve machine cost conservatively; faster shop clocks make the same real operation consume more paid game hours. The longer day setting therefore improves throughput and labor cost per job, while leaving full-shift wages unchanged. At the default twenty-minute day and twenty lifts, Tinker Fox at its requested $23/hour leaves **$935.87** and Ferret Engineer at $24/hour leaves **$876.62**, using the same twelve-hour/five-day contract and no equipment loan. The automated checks also cover a financed-machine payment and overnight schedules at five-, twenty- and sixty-minute days.

This is a workload plan, not guaranteed revenue: customer demand, player pallet staging, blocked output, focus and shared equipment affect actual production. Hiring more workers than available work/cutter capacity can lose money. The budget shows a break-even workload and warns when the chosen plan exceeds capacity. Available cash subtracts all earned unpaid wages, current bills and due loan installments/fees. Actual cash leaves only through the existing Payroll, Bills and Credit ledgers, so job-cost reporting does not charge wages twice.
