# Production bottlenecks, conveyor backlogs and delivery vans (0.9.0)

## What existed before (v0.8.0)
* `ProductionLine` already modelled belts as finite buffers: a station holds one token (a cylinder, or a crate of
  several at high output), pushes it onto its outgoing belt only if the belt has room, and is BLOCKED while it cannot.
  A slow machine therefore already starved the stations after it and blocked the ones before it.
* **But the end of the line was a bottomless sink.** The last belt delivered straight into the dispatch bay, which accepted
  any number of cylinders, and the van took the whole pile on every trip. Nothing could ever back up from dispatch.
* **Time away** credited `steady rate x time` with no reference to dispatch at all.
* In the retired direct-sales rules (`--direct-sales`, kept for the regression suites) everything that reaches the end of
  the line is sold on the spot. That path is unchanged.

Every place a cylinder leaves the line: (1) `ProductionLine._drain_exit` -> `FactorySim._dispatch_accept` (live play, classic
rules); (2) `FactorySim._on_line_shipped` (direct-sales rules only); (3) `FactorySim.apply_offline` (time away). There is no
other place where cylinders are created or destroyed. A safe checkpoint of the previous game is the git branch
`checkpoint/v0.8.0-classic` (and release v0.8.0).

## The rules now
**Transfer.** A station finishes a cylinder when its work is done. It passes it to its outgoing belt only if the belt has
room for one more (15 px spacing). Otherwise the cylinder stays in the station, the station is BLOCKED, progress is
kept (not lost, not advanced) and the machine animation stops. The belt's head cylinder enters the next station when that
station is empty, in order. Back-to-front processing each tick means space freed downstream is used in the same tick.

**Exit.** The last belt offers its head cylinder to the dispatch pad (`exit_cb`). The pad accepts as many cylinders as it
has room for (`DispatchBay.try_add`); a token that does not fit completely hands over what fits and keeps the remainder
on the belt. When the pad is full the head waits, the belt fills, the last station blocks, and so on up the line.

**Taps.** `ProductionLine.click()` adds work only to stations that hold an unfinished cylinder, and loads the first station
only if it is empty. A blocked station is skipped and reported (`last_blocked`) so the view can say LINE FULL.

**Van.** `LOADING` takes cylinders from the pad at a pace that fills the whole van in 2 s, never more than its capacity,
and leaves when full, when the pad has been dry for 1.2 s, or after 5 s, but never empty. `LEAVING` (3 s) -> paid ->
`AWAY` (turnaround) -> `ARRIVING` (1.6 s). The pad keeps filling while it is away.

**Conservation.** `injected = released + on the line`, and `made = sold + on the pad + aboard the van` (to 1e-6) - checked
every half second over a 400 s jam-and-deliver run, in the save round trip, and in a fuzz of awkward capacity/pad/away values.

**No deadlock.** The line is a pipeline with one sink that the van always empties, so a stopped line restarts whenever the
van returns. Any capacity/pad/away combination keeps delivering (tested for tiny, huge, and mismatched values).

**Offline.** `DispatchBay.throughput(line_rate)` works out, in closed form, what one round trip delivers: the pad fills during
the away time (never beyond its size), the van takes it and keeps loading for up to 5 s, never carrying more than its
capacity. A fully automated factory earns `min(machines, throughput)` per second for up to 8 h; what was waiting on the pad
at save time is delivered first. No per-frame simulation. The welcome-back box says when dispatch held output back.

**Saves.** Save version 7. The pad and van contents keep their format; a pad that holds more than the new limit (every
0.8.0 save) keeps everything and just refuses more until the van has worked it down. Upgrade levels carry over: `van_speed`
and `van_load` keep their levels (their meaning is now real), `dispatch_store` starts at 0. Queues (stations and belts,
including a part-delivered cylinder at the end of the last belt) are saved with the factory as before.

## Balance
Early tapping already produces 1.5-2 cylinders a second (one tap works every station), well above what the machines do
(0.4-0.9/s at ten minutes), so dispatch has to start comfortably above that: van 30, pad 45, 8 s away = 2.05 cylinders per
second. A 5x van or pad every ~8 levels then tracks the output of the machines (80/s at 110 minutes).

`tests/dispatch_economy_sim.gd` (two simulated players, two hours; baseline = v0.8.0):

| | 10 min | 30 min | 60 min | 2 h | held up at dispatch |
|---|---|---|---|---|---|
| v0.8.0 (unlimited pad) | £12.7k | £346k | £4.22M | £141M | never |
| 0.9.0, buys the cheapest upgrade first | £12.6k | £314k | £3.85M | £135M | 0% |
| 0.9.0, buys a fix only once the line has backed up | £12.3k | £269k | £3.35M | £121M | 24% at 20 min, 8% at 30 min, then 0-7% |

The first ten minutes are unchanged. A player who ignores dispatch sees the line back up for a while around 15-30 minutes,
and one tap on the red-flagged upgrade (a few hundred to a few thousand pounds) clears it. Upgrades cost 400-1,300,000 over
ten levels, a few percent of what has been earned by the time each is needed.

## Tests
`tests/run_dispatch_tests.gd` (113 checks): exit gate; conservation; the jam spreading from packing backwards in order;
taps cannot bypass capacity or earn; pausing and resuming with progress kept; the van takes only what is there, up to its
capacity, never leaves empty; return intervals; the pad never exceeds its size and belts hold a finite queue; upgrades;
both factories independent; save round trip (queues, blocked stations, pad, van timer); a real 0.8.0 (version 6) file;
offline bounded by dispatch and counted once; early game rarely held up; no deadlock. `tests/classic_touch_bot.gd` drives the
jam, the LINE FULL feedback and the fix with real injected touch events at the phone's screen shape.
