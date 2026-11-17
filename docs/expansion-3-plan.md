# Expansion 3 - Trade Contracts, Customer Orders & Dispatch: implementation plan

Written after reading the v0.4.0 code (checkpoint: branch `checkpoint/before-expansion-3`,
commit `c36c21c`). Everything below extends the existing architecture; nothing is rebuilt.

## What the code gives us

- Every cylinder a factory makes - clicked or automatic - leaves through **one door**:
  `ProductionLine.shipped(count)` -> `FactorySim._on_line_shipped`. Offline production leaves
  through `FactorySim.apply_offline`. Splitting output between "sell" and "contract" at those two
  points covers manual, automatic and offline production without double counting.
- Money is paid into one company balance (`GameState.cash`); each factory keeps `earned` /
  `cylinders_made`. Costs are deducted once, at sale (`profit_per_cylinder`).
- Simulation (`scripts/core`) is separate from rendering; `Game` ticks every unlocked factory at
  60 Hz, so switching view cannot affect production. Contracts must live in that same layer.
- Saves are versioned (`SaveManager`, v3) with step-by-step migration.
- Economy (balance bot): copper nets £8/cylinder, 22/min at 5 min, 630/min at 35 min, 15,000/min
  at 3 h; profit per cylinder grows ~40x via Polished Finish. Stainless nets £2,000/cylinder.

## Design decisions

1. **Core, no nodes.** New `ContractBook` (owned by `GameSession`) holds reputation, board offers,
   accepted contracts, history and timers. `ContractGenerator` is a pure function of
   `(seed, serial, market snapshot)`, so generation is reproducible and testable.
2. **Allocation.** Each accepted contract has an integer production share (% of its factory's
   output). Shares at one factory never exceed 100%. `route(factory, count)` hands whole
   cylinders to contracts with an error-diffusion accumulator (exactly the chosen share in the
   long run, never fractional cylinders) and the remainder is sold as before. With no active
   contract `route` returns 0 and the old code path is numerically identical (proved by a
   golden test recorded from v0.4.0).
3. **Pricing from the economy.** Contract value = quantity x the factory's *current* profit per
   cylinder x a margin (Trade ~+8-22%, Commercial +15-32%, Major +20-40%, wholesale volume deals
   slightly below market but rich in reputation). Quantities are minutes of the factory's
   *planning rate* (steady automatic rate, or a click-assisted estimate), so contracts track real
   capacity. A market-price guarantee means upgrades bought mid-contract can never make a
   contract pay less than selling normally.
4. **Deadlines.** Stored as time-left, ticked by the simulation. While away they run only for
   factories that actually run unattended (same rule as offline earnings, same 8 h cap).
   Failure: small reputation loss (never below the current rank), no bonus, premium offers
   paused for 15 min, and stock already built is sold at market price - nothing is destroyed.
5. **Offline.** The existing analytic offline rate is split piecewise (completion and deadline
   events) so contract progress, deadlines, freed shares and sales are all exact.
6. **Dispatch.** `READY -> DISPATCHING -> paid`. The dispatch timer lives in the simulation
   (deterministic, persisted, settles instantly if you were away), the view merely animates
   it: standing van pulls out, a delivery lorry reverses into the bay, a forklift loads <= 4
   pallets, the lorry leaves, payout + reputation + bonus are awarded exactly once.
7. **Reputation.** 6 ranks, persistent. Rank unlocks tiers, board size, better customers,
   premium offers and a 4th contract slot. Small orders stop giving reputation as you outgrow
   them, so it cannot be ground out.
8. **UI.** A Contract Board (Available / Active / History tabs) with finger-sized buttons,
   an ORDERS button with a badge in the HUD, reputation stars next to the cash, welcome-back
   contract summary. Allocation uses +/- and preset buttons rather than a slider.
9. **Future compatibility.** Contracts reference a factory id and a composed product, tiers and
   customers are data (`data/contracts.json`), gating uses "£ per minute potential" rather than
   product names. New products/factories appear automatically.
10. **Saves.** v4; v3 saves migrate with empty contract state. New per-factory counters
    (`cylinders_sold`, `cylinders_contracted`) default from existing data.

## Test plan

Automated (`tests/run_tests.gd` unchanged + new `tests/run_contract_tests.gd`): golden regression
against v0.4.0 numbers, generation determinism and balance bounds over thousands of contracts,
accept/allocate/complete/dispatch, no double counting invariants, payout exactly once,
reputation, deadlines, factory switching, offline + contracts, save/migration/corruption.
End-to-end (Xvfb): `tests/run_contracts_flow.sh` through the real game and touch input, plus
screenshots of the board, HUD and the dispatch sequence in both factories. The existing flow
tests, Windows export and Android export are run by CI as before; the Android emulator test is
extended with the contract flow.

## What testing changed (decisions that differ from the first draft)

The plan above was written before anything was measured. Building the tests and a policy-comparison
bot (`tests/contract_balance_bot.gd`) changed five things:

1. **Fractional, exactly-proportional routing instead of whole-cylinder error diffusion.** The
   end-to-end test found that at 2.5 cylinders/second the line batches 1.25 cylinders per item, so
   a whole-cylinder split leaked 20% of a 100%-allocated order into sales. Each shipment is now
   split exactly by share (the existing game already counts cylinders as floats), which also made
   the code simpler and removed a carry-over accumulator.
2. **Contract prices follow the list price (a price-adjustment clause).** A first version froze
   the price at offer time. Simulating whole games showed that in an economy that grows ~7x per hour
   the frozen premium evaporated before it was paid, and even cautious players ended 40% behind
   players who ignored contracts. Payout is now `quantity x current profit per cylinder x margin`
   (bonus likewise), so the premium is constant and the "market price floor" hack is gone.
3. **Shorter orders.** Cash parked for 25+ minutes costs far more than a 20% premium repays while
   upgrades pay back in minutes. Orders are now 0.6-1.5 (trade), 2-5 (commercial) and 6-14 (major)
   minutes of full-rate output.
4. **A new order never takes the last 20% of a factory.** Accepting every offer at the default
   share used to starve sales completely (-83%). The player can still raise shares by hand, and the
   board warns when a factory is nearly fully committed.
5. **Board pages rebuild only when the page's own data changes.** The touch test lost a tap when a
   new customer arrived while the Active tab was open.

Resulting balance over two simulated hours (ignoring contracts = 0%): sensible play
(trade + commercial, one order per factory) **+22%**; default shares including majors **+8%**;
timid (25% shares) **-6%**; accept-everything **-20%**.

## Verification summary

| Area | How it is verified |
|---|---|
| Existing gameplay unchanged | v0.4.0 scripted playthrough reproduced bit-for-bit (`tests/golden_v0_4_0.json`); all 241 original checks and the original flow tests pass |
| Generation reproducible and balanced | 6,300 generated contracts (every rank x capacity x price x seed) checked for bounds (value vs market, deadlines vs build time, tier gating, names, reputation) |
| Allocation, no double counting | invariants (made = sold + contracted, cash = sales + payouts) through busy multi-contract runs, clicking, batching, factory switching |
| Dispatch pays exactly once | repeated dispatch, mid-dispatch save/reload, offline settle |
| Deadlines, reputation | live, offline (event-stepped), floor rules, premium pause |
| Saves | v3 migration, round trip, corrupt data, transfer codes |
| UI | real-game flow through the actual buttons; touch flow with injected touches and a "no tiny buttons" check; screenshots reviewed |
| Not physically tested | a real Android device. The Android build and emulator test run in CI only |
