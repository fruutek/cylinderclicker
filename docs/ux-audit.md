# Mobile-first simplification: audit and what changed (0.7.0)

Guiding rule: **deep systems underneath, simple interactions on the surface.** Nothing was removed from the
simulation (warehouse, SKUs, orders, part deliveries, backorders, relationships, sales rep, saves, offline).
What changed is how much of it the player has to touch.

## 1. Audit of 0.6.0 on a phone in landscape (803x360 logical, 38 px safe inset)

| Where | Finding | Verdict |
|---|---|---|
| HUD bar | 9 items: cash, income, reputation stars, now making, profit each, cylinders made, output, ORDERS, FACTORIES, menu | Statistics nobody needs mid-game: keep cash + making + FACTORIES + menu |
| Right panel | Always on: 3 tabs (Upgrades / Machines / Products), 10-25 rows, locked "???" rows, hold-for-tooltip. 45% of the screen | A desktop sidebar. Replace with one card + four buttons |
| Warehouse state | A tiny label inside the factory art | Needs a clear bar on the main screen |
| A customer calls | Only a badge on ORDERS. ORDERS > CALLS tab > read a card with 4-5 two-line options | Surface the call itself, with at most 3 buttons |
| Order tracking | ACTIVE tab with shares, bars, SHIP NOW per contract; History; Customers; Sales rep table | Progress bars only; lorries go by themselves |
| Board contracts | ORDERS > AVAILABLE > ACCEPT > ACTIVE > SHIP NOW (5 taps, a separate dispatch decision) | Accept, and it ships when finished |
| Stock | 9-column table, 3 toggles, 2 action buttons, +/- per product, wholesale switch | AUTO STOCK or MANUAL; icons and quantities |
| Sales rep | A forecast table (shares, per minute, best stock, short, lost) | A helpful assistant: one or two sentences with one-tap buttons |
| Upgrades | Three tabs, in the order of the data file, prices only | One list, best next buy first, affordable first |
| Interruptions | Toast for every new offer, every call, every lorry | Quiet: the card is already on screen; the money counter is enough |

Taps for the things that matter: a telephone order **2 -> 1** (the card is on the main screen); a board contract
**5 -> 2** (ORDERS, ACCEPT); buying the next upgrade **1 + hunting through 3 tabs -> 1**; keeping stock right
**ongoing -> 0** (AUTO STOCK is the default).

## 2. The new surface

* **Main screen:** the factory (unchanged art and animation), a slim bar (cash, what is being made, FACTORIES,
  menu) and the *side deck*: how full the warehouse is, **one obvious thing to do** - a customer's order card if
  somebody is on the phone, otherwise the best next upgrade with a progress bar to afford it - and the four
  destinations **FACTORY | ORDERS | STOCK | UPGRADES**.
* **Order card:** `Midlands Plumbing - Wants 10 x Copper Direct - In stock 5 - Missing 5` with `SEND 5 + MAKE 5`,
  `SEND 5 ONLY`, `DECLINE`; or one `FULFIL ORDER` when everything is in stock (or `MAKE n` when nothing is). Behind the
  button the same reservations, production queue, part deliveries, backorders and lorries run as before.
  Calls are limited to two waiting, no more often than every 25 s; if nobody answers, the sales rep takes them.
* **Feedback instead of statistics:** "Delivered to X: +£158 - Customer happy! +3 relationship",
  "Delivery late! Customer unhappy."
* **STOCK:** a capacity bar, **AUTO STOCK (recommended, default) / MANUAL**, product tiles (pallet icon, quantity,
  how many are for customers, how many are being made; +/- targets only in MANUAL) and the sales rep:
  "Boss, we're running low on copper indirects." [RESTOCK RECOMMENDED], "We're missing orders because the warehouse
  is full." [UPGRADE WAREHOUSE], "Customers are waiting for 12 cylinders." [FOCUS ON BACKORDERS].
  Existing saves keep whatever they had chosen; only new games and migrated v0.5 saves start on AUTO.
* **UPGRADES:** one list - *best next buy*, *you can buy*, *saving up for* - in plain words ("Welding Robot - makes 52
  a minute", "Warehouse - +96 capacity", "Sales Rep Training - better demand forecasts"); the small `?` shows the
  full description. Prices and effects are unchanged.
* **ORDERS:** the customer on the phone, orders in progress as progress bars, big orders with one ACCEPT.
* **MORE DETAILS** (on ORDERS and STOCK) opens the full Contract Board with every table and statistic for anyone who
  wants them: nothing was deleted.

## 3. What is automated now

* Finished board contracts ship by themselves (`ContractBook.auto_ship_board`).
* AUTO STOCK keeps targets at the sales rep's recommendation; wholesale of surplus stays on; FOCUS ON BACKORDERS
  switches itself off when everyone has been served.
* The next upgrade is chosen for you (shelves when full, the machine limiting the line, cheap boosts while a machine is
  out of reach).

## 4. Responsive layout

The same screens serve both platforms: on a 640x360 desktop window the side deck is 196 px wide (navigation as a 2x2
grid); on a phone it takes the spare width (up to 340 px) inside the safe area, buttons are 40 px tall and the pages
scroll by finger. `--direct-sales` keeps the previous interface for the older end-to-end tests.
