# Expansion 4 - Warehouse, Stock Control & Customer Relationships: plan

Checkpoint: branch `checkpoint/before-expansion-4` (= v0.5.1, commit `d94a245`).

## 1. How money flows today (v0.5.1)

```
ProductionLine.shipped(count)
  -> FactorySim._on_line_shipped(count)
       contracted = ContractBook.route(factory, count)         # contract shares take cylinders first
       sold       = count - contracted
       cash += sold * profit_per_cylinder()                    # profit = price - material - manufacturing
       state.cylinders_made += count; earned += ...
offline: FactorySim.apply_offline -> floor(rate*seconds) -> same split
contract: payout at dispatch = qty x profit now x margin  (credit_contract_payout); failure -> release_stock (sold at market)
```
* Every cost is deducted exactly once, at the moment of sale, inside `profit_per_cylinder()`. Cash only ever
  moves by net profit, so nobody can be cash-starved by production.
* A cylinder is "made" and "sold" in the same instant. Income = production rate x profit, whether or not
  anyone wants the cylinders.
* Existing tests (241 + 808 checks, golden regression) assert exactly this behaviour.

## 2. The new model

```
click / machines -> token (SKU) -> line -> Warehouse.receive(sku) -> stock
customer phones  -> options -> reserve stock (+ backorder) -> Shipment -> lorry -> cash (net profit)
surplus above target -> wholesaler (limited, lower price)
```
* **Cash rule unchanged in spirit:** cash moves by *net profit at the moment of sale* (price x factors
  minus the SKU's material and manufacturing cost). No money is spent on production, so players can never
  be stranded, and costs are consumed exactly once (at dispatch / wholesale). Stock is therefore valued
  at today's cost, and a conservation identity holds per SKU:
  `made = stock + in-line + shipped + wholesaled`.
* **Warehouse per factory** (stock sits where it is made, dispatched from that factory's bay): integer stock,
  reserved, available; capacity in cylinders; whole units only (a fractional carry holds the rest); never
  negative; production stops when full (or surplus goes to the wholesaler if that is switched on - nothing
  is ever deleted).
* **SKUs** = factory + variant with its own price, material, manufacturing cost, work multiplier, demand
  weight, target, and optional specialist-machinery requirement (an upgrade). Copper Indirect is exactly
  the existing product, so existing numbers are the baseline.
* **Planner:** each time the first station can take work it asks "what should I make?": customer backlog
  first (earliest promise), then the SKU furthest below its target, within warehouse space. Clicks may
  stockpile beyond target. Offline uses the same decision function.
* **Orders:** telephone orders and board contracts share one reservation system and one dispatch/lorry
  pipeline. Order lines track ordered / reserved / shipped / outstanding; multiple shipments per order.
* **Customers** persist (relationship, history, preferences, patience, price sensitivity); loyalty
  moves slowly and is capped by how many orders have actually been completed.

## 3. Economy simulation before building (`tests/economy_prototype.gd`)

The real production engine and balancing bot, with income re-priced for a demand-limited business:

| Model | Earned after 2 h | vs v0.5.1 |
|---|---|---|
| v0.5.1 (sell every cylinder) | 52.3M | 0% |
| first guess: demand 0.85x, space gates income | 0.16M | -99.7% |
| demand 0.85x, make-to-order softens space | 11.7M | -78% |
| **skilled: demand 1.25x, +8% premium, cheap warehouse** | **54.5M** | **+4%** (stainless at the same 54 min) |
| average: 8% less effective income | 25.9M | -50% |
| careless: wholesale floor only (0.70) | 7.2M | -86% |

Findings that drive the design:
1. Growth is ~7x per hour, so any income shortfall compounds: an 8% loss is a 50% deficit after two hours.
   **Competent play must earn at least what v0.5.1 did.** Demand therefore exceeds capacity (about 1.25x) so
   production never idles when the product mix is right, and the premium for good relationships is a bonus.
2. Warehouse space must affect service (instant dispatch, fewer backorders), not gate sales: a small
   warehouse still sells through backorders.
3. The warehouse must be cheap early and cost ~3-6% of income overall.
4. The wholesale floor has to be generous enough (about 80% of normal profit, rate-limited) that a careless
   player is slower, not stuck.

## 4. Risks to existing saves, and what is done about them

| Risk | Mitigation |
|---|---|
| Income changes from "per cylinder" to "per sale" | stock mode starts with a warehouse sized to the factory's current output (free), auto-managed targets and wholesale on, so migrated factories keep earning |
| Active contracts hold cylinders that exist only as a counter | delivered units become reserved warehouse stock for that contract (over capacity allowed once); dispatching contracts keep their timer and are never deducted twice |
| Cylinders on the belts have no SKU | default to the factory's baseline SKU |
| Old tests assert immediate sales | the v0.5.1 behaviour stays available as a test mode ("direct sales"); golden regression still compares against v0.4.0 |
| Stale targets after huge growth | migrated saves start with auto-targets on; new games get one-tap "apply recommended" and a purchasable planner upgrade |
| Offline | same planner, stepped; standing orders replace unlimited calls; at most 3 call opportunities are queued |
| Save version | v5 (v4 and older migrate step by step) |

## 5. Milestones
A warehouse and stock display - B variants, targets, planner - C telephone orders, partial deliveries,
backorders, contracts on stock - D customers, relationships, sales rep - E balance, polish, release.
Each milestone ends with all suites green.

## 6. What was built, and the economy as measured on the real system

`tests/stock_economy_sim.gd` plays the shipped game for two hours with a simulated player (clicks, buys the cheapest
upgrade, builds factories) and compares it with the v0.5.1 rules (`--direct-sales`). Policies: **skilled** answers every
call with the best offer, keeps targets on the sales rep's recommendation, trains the rep and adds shelving only when
needed; **average** answers calls but turns 30% down and never touches stock; **careless** never picks up (the sales rep
takes the calls at a weaker price); **blind** only accepts orders that are already on the shelves.

| Policy | Earned after 2 h | vs v0.5.1 | Stainless plant at |
|---|---|---|---|
| v0.5.1 (sell every cylinder) | 52.3M | 0% | 54 min |
| **skilled** | **51.5M** | **-1.5%** | 55 min |
| average | 33.5M | -36% | 62 min |
| careless (rep answers) | 12.6M | -76% | 65 min |
| blind (stock only) | 3.7M | -93% | 77 min |

Skilled stock management matches the old game, careless play is slower but never stuck, and blind manufacturing is
clearly worse. What it took to get there (each one measured with the simulation):

* Calls unlock when there is something on the shelves, not when money has been earned (otherwise nothing could ever earn).
* A person clicking may keep building into a full warehouse and the surplus is wholesaled (85% of profit); the planner
  does not (it stops at the targets), so automation cannot overproduce.
* Demand follows what the factory really makes (a smoothed output rate x 1.6), order sizes are capped by shelf space,
  and ETAs count every product that shares the line.
* Targets follow the sales rep by default and never ask for more than 80% of the shelves.
* Customers who are not answered are served by the sales rep at 92% of the price; offline the rep takes every call
  except the last minute's (at most three), so unattended factories keep earning without a flood of calls.
* Trust is worth up to +16% on price; the wholesale floor is 85%.

## 7. Known limits

* The Android emulator test and the Windows build are exercised in CI; there was no physical Android device, so
  touch behaviour is verified by the injected-touch flow test and the emulator only.
* The APK is signed with a temporary CI key until the signing secrets are added (see the README); moving from 0.4.0
  needs Transfer Save, exactly as for 0.5.x.
* Only copper and stainless exist as factories; the SKU catalogue is the "smaller representative range" the brief allows.
