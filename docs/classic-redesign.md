# Back to the classic game (0.8.0): audit and decisions

## Which version was best?
* **v0.4.0** - clicking, the animated line, a van, upgrades, automation, the stainless plant. Simple, fun, mobile-friendly.
* **v0.5.x** - added contracts and a dispatch yard: the lorry and forklift were lovely, but the contract board, allocation
  sliders and reputation turned the main screen into a to-do list.
* **v0.6/0.7** - added a warehouse, SKUs, customers, relationships and a sales rep. Deep, but "business software".

The foundation is therefore the **v0.4.0 / v0.5.1 "sell what you make" economy** (which is pinned bit-for-bit to v0.4.0 by
the golden regression test) with its original shop-panel layout, plus three small additions.

## Checkpoint
The complete warehouse and customer-relationship game (v0.7.0) is preserved on the git branch
`checkpoint/v0.7.0-warehouse-ui` and in the v0.7.0 GitHub Release.

## What was removed from the game
Manual stock and warehouse management, stock targets and priorities, customer relationships, telephone calls with
part-delivery/backorder options, the sales rep and its forecasts, the contract board with output shares and dispatch
buttons, reputation stars, the SALES/STOCK/ORDERS screens, and most of the HUD statistics. The engine for the retired
systems still exists in `scripts/core` (and its tests) for the `--direct-sales` regression runs, but nothing in normal play
reaches it.

## What was kept
Both animated factories, all art, machines, belts, the blue insulation, factory switching, every upgrade and its price,
automation, offline progress, saves, Windows and Android.

## What was added
1. **Cylinder variants** (`data/variants.json`): six copper and six stainless types, unlocked by one-time **New Product**
   upgrades, chosen on the CYLINDERS tab. Build time, material cost, selling value and appearance differ; each specialised
   type earns 5-45% more per line-minute than the one before it.
2. **The delivery van** (`DispatchBay`, `VanYard`): finished cylinders wait on the pad, the van loads, drives away (you are
   paid) and returns. Automatic; never slows the line; **Faster Vans** and **Bigger Vans** upgrades (the vehicle changes too).
3. **Bonus orders** (`BonusOrders`): occasional, optional, one ACCEPT button, the factory works on it by itself, the bonus rides
   out on the next van; ignoring it costs nothing.

## Economy (tests/classic_economy_sim.gd, simulated player, 2 hours)
| Rules | 10 min | 30 min | 60 min | 2 h | Stainless built |
|---|---|---|---|---|---|
| original (v0.4.0/0.5.1) | £13.0k | £295k | £2.44M | £52M | 54 min |
| classic | £12.7k | £346k | £4.22M | £141M | 48 min |

Early pacing matches the original (the van delays cash by a few seconds); new products then arrive at 19, 27, 53, 69 and 90
minutes for a bot that buys the cheapest thing first (a human buys them sooner), so the mid game has milestones and the late
game grows faster. Copper stays useful after the stainless plant is built: both factories run all the time and both have
their own variants.

## Saves
Every earlier save loads. v0.5/0.6/0.7 stock on shelves, unfinished contract orders and the retired upgrades are paid out as
cash once (with a message); tooling that was bought unlocks the matching cylinder. Tested from v3, v4 and v5 saves in
`tests/run_classic_tests.gd` and through the real game in `tests/run_classic_flow.sh`.

## Android factory-name bug
The naming dialog pre-filled the 19-character default name and called `select_all()`. On Android the native text buffer
keeps that text and does not mirror the selection, and its 24-character limit counts old and new text together, so typing
stopped after about five or six letters (19 + 5 = 24). The field now starts empty with the name as a hint (blank keeps it).
Tested by typing real key events into the real dialog: "Telford Cylinder Works" (22), exactly 24 characters, 23 with symbols.
