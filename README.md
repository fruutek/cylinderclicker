# Cylinder Clicker

A cosy 2D pixel-art factory idle game. You run **Coppertop Cylinder Works**, a small British
hot water cylinder factory that you name yourself: click to work the line, sell copper cylinders, buy machines and
watch the factory slowly learn to run itself - then take on **customer contracts**, commit part of your
production to them and send a lorry out to collect the order.

Built with **Godot 4.7 + GDScript**. Runs on **Windows** and **Android** (landscape) from the same
code. Fully offline, local saves only, no ads, no accounts, no third-party assets.

![The classic factory: bonus order in the bar, van at the bay](docs/screenshot_classic_factory.png)

![Choosing what to make: six copper cylinder types](docs/screenshot_classic_cylinders.png)

![The stainless steel plant making the premium cylinder](docs/screenshot_classic_stainless.png)

## How to play it

**Easiest: download from the Releases page**

Open the repository's **Releases** page on GitHub and pick the latest release.

- **Android phone or tablet:** download `CylinderClicker-<version>-android.apk` on the phone and open
  it. The first time, Android asks you to allow your browser (or Files app) to install apps - allow
  it, then tap Install. The game is landscape only, needs no permissions and works offline.
- **Windows:** download `CylinderClicker-<version>-windows.zip`, unzip it and double-click
  `CylinderClicker.exe`. Windows may show a "Windows protected your PC" notice because the exe is
  not code-signed: choose *More info* > *Run anyway*.

Every push also builds both versions: open the **Actions** tab, pick the latest green run and
download the `CylinderClicker-android` or `CylinderClicker-windows` artifact.

**Run from the project**

1. Download Godot **4.7.x** (standard version) from <https://godotengine.org/download/windows/>.
   It is a single exe - no installer.
2. Start Godot, choose **Import**, select this folder's `project.godot`, then press **F5**.

### Moving a save between Windows and Android

Saves are stored separately on each device (`%APPDATA%\CylinderClicker\savegame.json` on Windows,
the app's private storage on Android). To carry a factory across:

1. On the old device open the main menu, choose **Transfer Save** > **Copy save code**.
2. Paste the code into an email or message to yourself.
3. On the new device copy that code, open **Transfer Save** and choose **Paste save code**.

The old device keeps its save; nothing is deleted.

### Android signing

Android only lets a new APK update an installed one if both are signed with the same key.
Builds are signed in one of two ways:

* **With your own permanent key** - add these repository secrets (Settings > Secrets and variables > Actions):

  | Secret | Value |
  | --- | --- |
  | `ANDROID_KEYSTORE_BASE64` | the keystore file, base64-encoded |
  | `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
  | `ANDROID_KEY_ALIAS` | `cylinderclicker` |

* **Without secrets** - the **shared test key** committed in `tools/ci/cylinderclicker-shared-test.keystore` is used and the
  APK is named `...-android-testkey.apk`. From 0.8.0 on every such build uses this one fixed key, so they update each other
  in place. It is *not private* (anyone can read it), which is fine for a hobby game but not for a store release. Builds
  before 0.8.0 (0.4.0's permanent key, and the throw-away keys of 0.5.x to 0.7.x) cannot be updated by it: uninstall first,
  or use **Transfer Save** to keep your factory.

## Controls

On Android everything is done by touch: tap the factory to work (two thumbs both count), tap a
shop row to buy, **press and hold a row** for its details, drag the shop to scroll, and use the
phone's **Back** button or gesture for the pause menu.

| Input | Action |
| --- | --- |
| Left-click the factory floor, or **Space** | Work every station (the core click) |
| Click a shop row | Buy that upgrade / machine |
| Hover a shop row | Tooltip with what it does and what the next level gives |
| **1 / 2 / 3** | Upgrades / Machines / Products tabs |
| **F** or the FACTORIES button | Factory overview: see every factory, switch between them, build new ones |
| **C** or the ORDERS button | The Contract Board: customer offers, your accepted contracts, production shares, dispatch |
| **Esc** or the gear button | Pause menu (resume, save, settings, rename factory, return to main menu, quit) |
| **F11** | Toggle fullscreen |

## Cylinder types, the delivery van and bonus orders

**Cylinder Clicker is a clicker / idle factory game.** Click to speed up the line, watch the cylinders travel through
the animated machines, get paid when the delivery van drives away, buy upgrades, automate every station, unlock new
cylinders and a bigger factory, and come back later to find the factory has kept working.

- **Cylinder types.** Each factory makes one cylinder at a time. The standard cylinder is free; the others are
  unlocked by buying **New Product** upgrades and chosen on the **CYLINDERS** tab (or tap **NOW MAKING** in the bar):
  Copper - Standard, Direct, Indirect, Slimline, Horizontal, Twin-Coil; Stainless - Standard, Direct, Indirect, Slimline,
  Horizontal, Premium. Each has its own price, build time, selling value and look on the belt (a tint, a slimmer, wider
  or taller body). Specialised cylinders are worth more but take longer, so each earns about 5-45% more per minute of
  line time than the one before it, never enough to make the older ones worthless (`data/variants.json`).
- **The delivery van.** Finished cylinders wait on the pallets of the outbound pad. The van loads them, drives out of
  the door - *that is when you are paid* - stays away for its turnaround and comes back, all by itself. It never slows
  the factory down: cylinders made while it is out just wait for the next trip. **Faster Vans** shorten the turnaround and
  **Bigger Vans** carry bigger loads (and the van becomes a lorry); both add a small delivery bonus.
- **Bonus orders.** Now and then a customer offers an order ("Midlands Plumbing wants 20 Indirect: +£120"). One button,
  **ACCEPT**, in the bar. The factory switches to that cylinder by itself, and when the last one is made the next van
  takes the bonus with it. Ignore an offer and it simply goes away; nothing is ever mandatory (`data/bonus_orders.json`).
- **Old saves.** A save from any earlier version loads. Unfinished contract orders, stock that was on the warehouse
  shelves and the warehouse / sales-rep upgrades are converted to cash (once, with a message), tooling you had bought unlocks
  the matching cylinder, and everything else is untouched. `--direct-sales` on the command line runs the v0.5.1
  rules and interface instead (the older end-to-end tests use it). The warehouse and customer-relationship version of
  the game is preserved in git on the branch `checkpoint/v0.7.0-warehouse-ui` (release v0.7.0).

## What is in the game

- **Two factories.** The Copper Cylinder Works you start with, and the Stainless Steel Plant: a
  second building with its own eight-stage line (Sheet Prep, Laser Cut, Rolling, TIG Weld, Coil
  Fit, Testing, Casing, Packing), its own machines, upgrades, artwork and statistics. It costs
  £1,000,000 to build once the copper works is fully automated and has earned £500,000.
- Every factory you own keeps producing whichever one is on screen, and all sales go into one
  company cash balance. Offline earnings cover every automated factory.
- Stainless cylinders sell for far more but carry material and manufacturing costs, take much
  longer to build and need expensive machines - slow at first, more profitable in the long run.

- One copper cylinder production line with six stations: Cutting, Rolling, Welding,
  Pressure Test, Insulation, Packing, then dispatch to the van.
- Cylinders are visible objects that ride the conveyors and change appearance at each stage
  (sheet > cut sheet > rolled tube > welded cylinder > tested > blue foam-insulated > boxed).
- Clicking adds work at every station. Each station can be automated with its own machine,
  and each machine can be levelled up (speed doubles at levels 10, 25, 50...).
- Real bottlenecks: belts are the buffers, so a slow station makes cylinders queue up behind
  it, blocks the station before it (yellow **!**) and starves the ones after. The Machines
  tab names the slowest machine once the line is fully automated.
- Upgrades: Better Hand Tools (faster production), Polished Finish (higher selling value),
  Conveyor Motors, Rallying Whistle (keeps clicking useful late on) and Lean Workflow.
  Later ones reveal themselves as your lifetime earnings grow.
- Economy: sale price minus material cost = profit per cylinder; exponential upgrade costs.
- Main menu (New Game, Continue, Settings, Quit) and an in-game pause menu on Esc that
  freezes the factory while it is open.
- Name your factory when you start (up to 24 characters; the field starts empty with the default as a hint, so an
  Android keyboard has the full 24 to use); the name is painted on the wall sign and can be changed from the pause menu.
- Saving: manual save from the pause menu, autosave every 30 seconds, and on returning to
  the menu or quitting. Saves include the cylinders currently on the line, keep a backup
  copy and use a versioned format (older saves are migrated).
  Saves live in `%APPDATA%\CylinderClicker\savegame.json`.
- Offline progress: a fully automated line keeps earning while the game is closed (up to
  8 hours), with a welcome-back summary.
- Tutorial hints, sound effects, a music loop, floating cash pop-ups and particles.
- A **CYLINDERS** tab (also: tap NOW MAKING) to choose what the line makes - see the next section.

## Project layout

```
data/        JSON definitions - edit these to rebalance or add content
  contracts.json  customer contracts: ranks, tiers, customers, margins, deadlines, dispatch timing
  factories.json  the factory buildings, their unlock requirements and cost
  stations.json / upgrades.json                      the copper works' line and upgrades
  stainless_stations.json / stainless_upgrades.json  the stainless plant's line and upgrades
  products.json   materials x ranges x variants (products are composed, not hard-coded)
scripts/core/     pure game logic - no nodes, no rendering (fully unit-tested)
  production_line.gd   deterministic line simulation (stations, belts, batching)
  game_session.gd      the company: shared cash, every factory, unlocking, offline progress
  factory_sim.gd       one factory: its upgrades, economy and production line
  factory_def.gd       a factory's data definition; factory_state.gd its saved state
  stat_block.gd        turns upgrade levels into stats
  product_catalog.gd   composes products from parts
  contract_book.gd     trade contracts: reputation, the board, allocation routing, deadlines, dispatch, offline
  contract_generator.gd  reproducible customer orders from (seed, serial, market snapshot)
  contract_rules.gd / contract.gd  the contract data and its rules lookups
  save_manager.gd      versioned saves with migration and backup
  num_format.gd        number/currency formatting (K, M, B ... then scientific)
scripts/autoload/ Game (fixed-timestep loop, saving, menu/game switching) and Sfx (audio)
scripts/menu.gd   main menu; scripts/main.gd is the factory scene
scripts/view/     factory_view.gd - draws the factory from the simulation state; dispatch_yard.gd - the
                  pallet pad and the delivery sequence
scripts/ui/       HUD, shop, tutorial, dialogs, theme
assets/           generated sprites, font and audio
tools/            Python generators for all art, the font and the audio
tests/            headless tests, a balancing bot and a screenshot bot
```

### Architecture notes

- **Simulation is separate from rendering.** `GameSession`, `FactorySim` and `ProductionLine`
  never touch the scene tree; `FactoryView` only reads the one factory on screen. All unlocked
  factories are ticked every step, so switching view cannot lose or duplicate production.
- **Adding a factory is mostly data:** an entry in `factories.json`, a stations file, an upgrades
  file and its sprites (named in the stations file's `view` block). The same logic runs in the game, the tests
  and the balancing bot.
- **Scaling.** A token on the belt is a *batch* of cylinders. Early on a batch is exactly one
  cylinder. When machines could exceed about two items per second, each new item carries
  proportionally more cylinders instead, so the number of simulated and drawn objects stays
  small no matter how large production becomes (tested at roughly 100,000 cylinders/min).
- **Big numbers.** Values are 64-bit floats (up to about 1e308), clamped at 1e300 and always
  formatted through `NumFmt`. If that is ever outgrown, only `NumFmt` and the arithmetic in
  `GameSession` need to change.
- **Contracts are part of the same simulation.** Every cylinder a factory ships, and every offline
  catch-up, passes through one door (`ContractBook.route` / `offline_factory`) that splits it between
  contracts and sales, so manual, automatic and offline production share one set of rules and nothing
  is counted twice (made = sold + contracted, tested through whole playthroughs). With no active
  contract the split returns 0 and the old arithmetic is untouched: a scripted 30-minute playthrough
  plus 2 hours away is identical to v0.4.0 to the last bit (`tests/golden_v0_4_0.json`). The dispatch
  timer lives in the simulation (saved, resumable); `DispatchYard` only animates it. Contract
  generation is a pure function of `(seed, serial, market snapshot)`, and uses factory ids and
  composed products, never copper or stainless by name, so new factories and products get orders
  without code changes.
- **One game, two platforms.** Android uses the same scenes and scripts. The layout is computed
  from the screen size (640x360 gives the desktop arrangement exactly; a phone's wider screen
  gives the shop more room), and `UiTheme.touch` switches on finger-sized controls.
- **Determinism.** The simulation runs on a fixed 60 Hz step; identical inputs give identical
  results. Offline earnings use the analytic bottleneck rate.
- **Saves are versioned.** `SaveManager` upgrades old saves step by step, ignores unknown
  upgrades and refuses saves from a newer version. Version 4 adds the contract book (reputation,
  offers, accepted contracts with progress, shares and deadlines, history); version 5 adds the warehouse
  (per-factory stock, reserved, counters, targets, priorities), the sales office (customers, relationships,
  waiting calls, forecast history) and the order fields; older saves load and migrate step by step.
- **Warehouse accounting.** Cash only ever moves by net profit at the moment of sale (price less the product's
  material and making cost), so production never needs money up front and a player can never be stranded. The
  `Warehouse` keeps whole-unit stock, reserved and fractional carry; `StockPort` is the contract book's only way
  to reserve, release or ship it; `SalesOffice` owns customers, calls and the forecast and creates ordinary
  `Contract`s; `FactorySim` hosts the planner. None of them touch the scene tree.

## Development

```bash
godot --headless --path . --import                 # first time only
godot --headless --path . -s tests/run_tests.gd    # logic tests
tests/run_save_flow.sh                             # real save > quit > load > offline flow
tests/run_menu_flow.sh                             # menus, naming, pause, saving and restart, end to end
tests/run_expansion_flow.sh                        # old save > build stainless > switch > restart > offline
godot --headless --path . -s tests/run_contract_tests.gd   # contracts: generation and balance, allocation, dispatch, reputation, deadlines, offline, saves
tests/run_contracts_flow.sh                        # old save > orders > shares > dispatch > restart mid-dispatch > two hours away (needs xvfb)
tests/run_touch_flow.sh                            # phone layout, touch input (including the Contract Board), Android pause/resume (needs xvfb)
tests/android/run_emulator_test.sh                 # the same inside the real APK on an emulator (run by CI)
```

Screenshots from the real Android emulator run are in `docs/android/` (add `[android-screenshots]`
to a commit message to refresh them).

```bash
godot --headless --path . -s tests/balance_bot.gd  # pacing report from a simulated player
godot --headless --path . -s tests/contract_balance_bot.gd -- --hours=2   # the same game under different contract policies
python3 tools/gen_art_contracts.py                 # regenerate the pallet, forklift, lorry and icon sprites
python3 tools/gen_audio_contracts.py               # regenerate the dispatch sounds (needs numpy)
python3 tools/gen_art.py                           # regenerate sprites (needs Pillow)
python3 tools/gen_art_stainless.py                 # regenerate the stainless plant sprites
python3 tools/gen_font.py                          # regenerate the pixel font
python3 tools/gen_audio.py                         # regenerate audio (needs numpy; music is then converted to .ogg with ffmpeg)
```

## Assets and licences

Everything in `assets/` is original to this project and generated by the scripts in `tools/`:
the sprites are drawn procedurally, the pixel font was hand-authored glyph by glyph, and the
sounds and music are synthesised from oscillators. There are **no third-party assets**.
The game runs on the Godot Engine (MIT licence).

## Roadmap (not in this version)

- More factories: Thermal Stores, Pre-Plumbed and the specialist variants (contracts will pick them up).
- Larger company contracts and supplier purchasing and negotiation for material costs.
- Buy-multiple buttons, achievements, more ambience and animation.
