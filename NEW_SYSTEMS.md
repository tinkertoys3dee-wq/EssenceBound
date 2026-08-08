# What changed, and what to check in Studio

Two commits on `claude/retention-and-captivation`. Everything below is
either a bug fix to existing code or a self-contained new file — no
existing gameplay system was restructured.

---

## 1. The bug that was causing the bad metrics

`src/Shared/EssenceMultiplier.luau` multiplied **every** essence reward in
the game by `ShadowEssence ^ 0.2`. A new player starts with 0 Shadow
Essence, and `0 ^ 0.2 == 0` in Lua — so every click and every idle tick
paid out **zero**, permanently, for every new player. The floating "+N"
text on collected orbs literally read "+0", currency never moved, and no
upgrade was ever affordable.

That single line explains all four bad numbers at once: 3.2 min average
playtime, ~2% Day-1, 0% Day-7, and the 8-Robux ARPU (players who bought a
boost to escape the stuck feeling got nothing, because boosts routed
through the same zeroed multiplier).

Fixed so a 0 balance is neutral (`(ShadowEssence + 1) ^ 0.2`) rather than
annihilating. **This is the change that matters most — everything else is
secondary.**

## 2. Other fixes

- **Auto Absorption gamepass did nothing.** `CursorCollection.client.luau`
  had `if player:GetAttribute(1907677938) and false then` — the `and false`
  made the paid feature permanently unreachable. Removed.
- **Open data exploit.** The `UpdateData` remote let any client write
  arbitrary paths into their own PlayerData (currency, rebirths, anything)
  with no allowlist. Restricted to the three roots the game actually uses
  client-side: `Settings`, `SeenTutorial`, `HollowedMilestones`.
- **Tutorial opened on a Robux pitch.** The Shop step was step 1, before
  the player had played at all. Reordered so it teaches click → hover →
  collect first, and it now explains the orb's energy bar (previously an
  unexplained hard wall after ~12 clicks that reads as a bug).
- **Energy bar eased for the early game** (`BASE_MAX_HP` 100→150,
  `BASE_REGEN_RATE` 2→3.5) in `EssenceOrbController.luau`.
- Discovery popup showed `Odds: 50` (a raw spawn weight) instead of
  `Odds: 1 in 2`.
- `GetRandomEssence` could return `nil` when floating point left the roll
  a hair above the final cumulative weight.
- Loading screen preloaded assets one at a time in a loop; now batched
  into a single `PreloadAsync` call.
- Removed leftover debug prints (including a `print('fucg')`).

## 3. New engagement systems

Three new files, plus new fields in `DefaultPlayerData`:

| File | Role |
|---|---|
| `src/Shared/ProgressionConfig.luau` | All tunable numbers — rewards, quest pool, chest tiers |
| `src/Server/ProgressionService.server.luau` | Server-authoritative logic, grants, promo codes |
| `src/Client/ProgressionHud.client.luau` | All the UI, built in code |

**Daily login streak** — 7-day cycle, escalating; day 7 pays out big plus
a 30-min 1.5x boost (reuses the existing potion system). Missing a day
resets to day 1. Nothing is ever permanently lost and there's no way to
pay to restore a streak.

**Daily quests** — 3 goals, rotating each UTC day, the same for every
player that day. Tracks orbs collected, clicks, crits, upgrades bought,
essence earned, rebirths.

**Playtime chests** — claimable at 2, 5, 10, 18, 30 and 45 minutes of a
single session, then a repeating one every 15 min. Progress is
per-session and resets on rejoin *on purpose*: because rewards escalate,
staying is always better than rejoining, so it can't be farmed.

**Promo codes** — a `CODES` table near the top of
`ProgressionService.server.luau`. Codes live **server-side on purpose**:
anything in ReplicatedStorage can be datamined, so codes kept there get
redeemed before you announce them. Currently live:

```
LAUNCH  WELCOME  ESSENCE  ORBHUNTER  BOOSTME
```

To add one, add an entry to that table (keys in CAPS — input is
upper-cased before lookup) and publish.

## 4. Game feel pass

New `src/Shared/Juice.luau` — a shared toolkit (pitch-varied sound, scale
punch, shake, expanding rings, particle bursts, floating text, animated
count-up, unified button feel). Applied across `OrbClicker`,
`CursorCollection`, `UIManagement` and `ProgressionHud`.

**A real bug it fixed:** `HoverClickTween` squishes the orb's `UIScale` to
0.95 on mouse-down, then `OrbClicker`'s `popTween` yanked the same
property to 1.1 a frame later — the press-squish existed in the code but
was never visible. The manual click path now leaves scale to
`HoverClickTween`.

Also: the orb click has escalating feedback on rapid clicking (pitch,
burst size, a bigger beat every 10), out-of-energy shakes and says
"Recharging!" instead of a bare red flash that read as a bug, currency
counters roll up instead of snapping, crits announce themselves, and the
global button handler no longer replays one shared `Sound` at a fixed
pitch (which cut itself off and got grating fast).

Everything here is cosmetic. No reward, rate or spawn count is touched —
a 20-click streak is worth exactly the same as the first click.

## 5. Visual environment

| File | Role |
|---|---|
| `src/Client/AmbientBackground.client.luau` | Parallax motes, drifting colour wash, vignette |
| `src/Client/OrbAura.client.luau` | Rings, breathing glow and orbiting motes around the great orb |

The game is played entirely in a ScreenGui, so whatever sits behind the
orb *is* the environment — there's no 3D world doing that job.

Both live in their own ScreenGuis at negative `DisplayOrder` (−10 and −5)
so they render behind everything else without any existing UI changing.
Motes are created once and recycled forever, motion is TweenService-driven
rather than per-frame, and counts scale down on small screens.

The aura also dims and cools as orb energy drains, so that state is
readable from the orb itself and not only from the bar beneath it.

> ⚠️ **If you don't see the background:** `MainGui` probably has an opaque
> full-screen frame behind everything. Set its `BackgroundTransparency` to
> 1 (or delete it) and the ambient layer will show through. The repo can't
> tell — StarterGui properties were never synced.

## 6. Early-game pacing pass

Targeted at "people leave in the first few minutes because it's slow."
Investigated the actual numbers rather than guessing — here's what a
brand-new, upgrade-less player was actually experiencing:

- **0.9s hover-charge on every single collection**, forever, from orb #1.
  This sits directly in the path of every reward in the game. → **0.5s.**
  `swift_collection_1/2` can still shave off up to 2.3s combined, so the
  upgrade line reaches the 0.15s floor comfortably either way — nothing
  about that upgrade got less meaningful.
- **0% base crit chance**, with the first *guaranteed* crit not landing
  until click #20 (`BASE_GUARANTEED_CRIT_STREAK`). A brand-new player
  could easily have a whole short session with zero crits — meaning they
  never saw the game's biggest visual payoff. Two changes: the streak
  constant → **16** (kept high enough that a maxed
  `guaranteed_crit_streak` upgrade — max reduction −10 — still lands on
  6, above the floor of 4, so all 5 levels of that upgrade stay
  meaningful), and the **first non-fragment orb a player ever spawns is
  now a guaranteed crit** (`src/Client/OrbClicker.client.luau`, gated by
  a new one-time `SeenFirstCrit` flag, same pattern as `SeenTutorial`).
  This is a real crit, not just a visual — it pays the actual crit
  multiplier server-side too.
- **Loading screen forced wait** (`MinDisplayTime` + `GraceAfterComplete`)
  was 2.25s + 1.5s regardless of theme. Trimmed to 1.4s + 0.8s. This is a
  pacing change only — none of the ominous content itself was touched.

**Correction (balance pass, see section 9):** an earlier version of this
doc claimed `root_awakening`'s effect was dead/unwired. That was wrong —
re-checked while auditing the whole tree's numbers this pass, and
`src/Client/OrbClicker.client.luau`'s `SpawnOrb` has always read
`player:GetAttribute("root_awakening")` and applied `2^power` to every
orb's `EssenceValue` (present since the very first commit, verified via
`git log -S`). The upgrade genuinely doubles essence per level exactly as
its description says. Leaving this note here so nobody re-"discovers"
the same false alarm.

## 7. Shadow Sanctum (Shadow Essence finally has a use)

Shadow Essence was a **dead-end currency**. Its orbs spawn at the same
rate as Earth Essence and it feeds a passive multiplier, but every upgrade
in `TreeUpgrades` costs `EarthEssence` — so there was nothing to spend it
on.

| File | Role |
|---|---|
| `src/Shared/SanctumUpgrades.luau` | Definitions, costs, effect math |
| `src/Server/SanctumService.server.luau` | Purchase validation + persistence |
| `src/Client/SanctumPanel.client.luau` | The panel UI (🌑 button, left edge) |

Four permanent upgrades, all bought with Shadow Essence:

| Upgrade | Effect per level | Max |
|---|---|---|
| Umbral Focus | +5% essence | 10 |
| Deep Well | +40 max orb energy | 10 |
| Swift Shadows | +0.6 energy/sec regen | 8 |
| Wider Reach | +4 collection radius | 8 |

They stack **on top of** the Earth tree, and live in
`PlayerData.SanctumUpgrades` — separate from `PlayerData.Upgrades`, so a
rebirth (which wipes the Earth tree) never touches them.

**Spending doesn't make you weaker.** The multiplier used to read your
Shadow Essence *balance*, which would mean buying anything shrank your own
multiplier — a trap where using the shop is a downgrade. It now reads
`LifetimeShadowEssence`, which only ever increases. Existing saves are
migrated on load, so nobody loses multiplier when this first ships.

To retune, edit the `UPGRADES` table in `SanctumUpgrades.luau` — costs,
levels and effects are all there, and the server and UI both read it, so
they can't drift apart.

### Bug fixed: panel showing 0 despite a real balance

`SanctumService`'s join logic did a blind `task.wait(1)` before reading
the balance. `PlayerDataHandler` creates the Shadow Essence leaderstat
*after* a DataStore load that can easily take longer than a flat
1-second guess, especially for a large save. When the stat wasn't ready
yet, the panel showed 0 no matter the real balance, **and the live-update
listener never got attached** — so it stayed wrong for the whole session,
not just a brief flash. Now waits for the actual leaderstat via
`WaitForChild` before ever reading it, and the panel also fires a
`RequestSanctumSync` every time it opens as a self-healing backstop.

### The full upgrade list (12 total)

**Enhancements** (linear stat boosts):

| Upgrade | Effect per level | Max | Hooks into |
|---|---|---|---|
| 🌑 Umbral Focus | +5% essence | 10 | `EssenceMultiplier` |
| 🔋 Deep Well | +40 max orb energy | 10 | `EssenceOrbController` |
| ⏳ Swift Shadows | +0.6 energy/sec regen | 8 | `EssenceOrbController` |
| 🎯 Wider Reach | +4 collect radius | 8 | `CollectionUpgrades` |
| 🎲 Dark Fortune | +2% crit chance | 10 | `CriticalsController` |
| 💠 Umbral Fracture | 4% cheaper clicks | 8 | `EssenceOrbController` |
| 🧲 Void Magnetism | +0.12 magnet pull | 8 | `CollectionUpgrades` |
| ♾️ Shadow Overflow | +3 max active orbs | 8 | `CollectionUpgrades` |

Every one stacks *additively* with the matching Earth Essence tree line
rather than replacing it, and each is clamped where the base game already
clamped. Umbral Fracture's clamp matters most: combined with
`fracture_efficiency` it could otherwise push the cost reduction past
100%, making clicks *refund* energy and the orb infinitely clickable.

### Relics — periodic, automatic, highly visual events

Four Sanctum purchases that aren't stat bumps — they're timed events that
fire on their own and demand attention when they do:

| Relic | Cost | Interval (lvl 1 → 2) | Effect |
|---|---|---|---|
| 🔨 Shadow Hammer | 500 → 3000 | 45s → 28s | Telegraphed slam on the great orb, +4 → +7 bonus real orbs |
| 🌌 Void Laser | 700 → 4200 | 55s → 32s | Beam sweeps the field, instantly collects everything active |
| ⌛ Chrono Rift | 900 → 5400 | 70s → 45s | 6s → 10s window where collection is instant, no hover charge |
| 🌘 Shadow Eclipse | 1100 → 6600 | 90s → 60s | Sky darkens, 25s → 40s of 1.5x essence on everything earned |

Chrono Rift grants a temporary *state* rather than a one-shot payout, so
for its duration the whole loop plays differently — sweep the cursor and
everything it touches is gathered immediately. It reuses the exact
instant-collect path `essence_magnet_field` permanently unlocks, so the
two can't drift apart, and a full-screen tint makes the altered state
unmistakable.

Hammer, Laser and Rift all fire through the **exact same functions** a
real click/collection already uses (`SpawnOrb`, `CollectEffect`) — no new
trust surface, payout validated server-side through the identical path
everything else uses.

**Shadow Eclipse is the odd one out, deliberately.** It grants a real
essence *multiplier* (via the existing `PotionTimerService`, reusing the
`EssenceX15` effect that potions already use) rather than routing through
an already-trusted gameplay remote — so unlike the other three, its
timing has to be owned by the **server**, not the client. If the client
timed its own Eclipse, a forged "trigger now" request could be spammed to
stack `PotionTimerService`'s "Extend" mode into an unbounded free boost.
`SanctumService.server.luau` runs one bounded per-player loop that ticks
the interval, applies the boost, and tells the client only "a cycle of N
seconds just started" / "the boost is live for N seconds now" — cosmetic
countdown and screen effect, never a decision. That server loop uses
bounded polling rather than a bare `GetAttributeChangedSignal():Wait()`
to gate on relic ownership, since a server-side coroutine (unlike a
client one) is *not* torn down automatically when the player leaves and
would otherwise leak forever for anyone who never buys the relic.

Every relic gets a **live countdown pill**, all four sharing one bar via
`Juice.RegisterRelicPill` / `Juice.GetRelicBar` in `Juice.luau` — bottom-
center, auto-laid-out left to right (Hammer, Laser, Rift, Eclipse) by a
`UIListLayout` rather than each ability hand-building and independently
positioning its own `ScreenGui`. Adding a fifth relic pill in the future
is a single `Juice.RegisterRelicPill(...)` call with the next
`Order` — no new positioning math, and no risk of two pills overlapping.

### Panel layout

With twelve upgrades the list needed real structure:

- **`UIPadding` on the scroll frame** instead of negative row widths. The
  right inset clears the scrollbar so rows can't slide underneath it, and
  the bottom inset stops the last row butting against the panel edge.
- **Section headers** (`ENHANCEMENTS` / `RELICS`) with `LayoutOrder`
  spacing, since an unbroken list gave no way to tell the two very
  different kinds apart without reading every description.
- **Panel grown** 0.62 → 0.72 tall to hold it.
- **Row hover** — rows are Frames, but `GuiObject` still fires
  `MouseEnter`/`MouseLeave`, so the whole row responds to the cursor
  rather than only the small Buy button.
- **Affordability pulse** — one shared loop so every affordable row
  breathes *in sync*; staggered pulses read as noise, a single rhythm
  reads as "these are the ones you can buy."

Extending `SanctumUpgrades.luau`'s schema with `Kind = "Relic"` +
`Levels[level] = {Interval, BurstCount?/WindowSeconds?/BoostSeconds?}` was
the only change needed —
`SanctumService` and `SanctumPanel` already read costs/levels/
descriptions generically, so the whole server + panel pipeline picked
these up with zero changes to either file. Shadow Eclipse's own server
loop was the one genuinely new piece of plumbing, for the server-owned-
timing reason above.

### Orb cap was silently making paid upgrades pointless

`BASE_MAX_ACTIVE_ORBS` in `OrbClicker.client.luau` was **400** — high
enough that a player would essentially never hit it during normal play.
That quietly made two real, purchasable upgrades (`overflow_capacity` on
the Earth tree, `sanctum_overflow` in the Sanctum) worth buying in name
only, since their whole effect is raising a cap nobody was ever close to.
Dropped to **40**, so the base cap is something a busy screen can
actually reach, and the overflow upgrades (+60 / +24 respectively) go
back to being a real, felt increase in how much can be on screen at once
rather than a number that never mattered.

### Storm arrival now announces itself

The automatic Essence Storm (every 5 minutes minimum, even at zero
upgrades — so most sessions that clear the first few minutes will see
one) used to land as nothing but a text label quietly updating in the
corner. It's the game's biggest recurring free-bonus moment and was
landing completely flat. Now gets a screen flash, a big "⚡ ESSENCE
STORM! ⚡" (or "✨ GOLDEN STORM! ✨") callout, and a distinct sound —
golden storms ring at a higher pitch so the rarer version is audibly
distinct before the label is even read. Purely cosmetic; the storm's
actual duration, spawn rate and golden roll are untouched.

All rewards scale with rebirth count, so they stay meaningful for a
returning player without breaking a new one. Everything pays out in
ordinary in-game essence — nothing here costs Robux or pressures a
purchase.

### How it integrates

Purely additive. Quest progress is tracked by attaching **additional**
listeners to the existing `ClickOrb` / `Collection` remotes (Roblox fires
every connected listener) and by watching attributes the upgrade and
rebirth systems already set. No existing gameplay file was modified to
support this, and deleting the three new files reverts it completely.

All UI is built with `Instance.new` rather than living in StarterGui —
the same approach `LoadingScreen`, `Tutorial` and `NewDiscovery` already
use — so **nothing needs to be hand-built in Studio**.

---

## 8. Prestige Shop (Rebirth Currency finally does something)

Rebirth Currency ("Prestige Shards") was half-built already: every rebirth
granted `RebirthModule.BASE_REBIRTH_CURRENCY_GRANT` (1) Shard, plus a bonus
from the Earth tree's **Ascension Insight** upgrade — but that upgrade's
own in-game description literally read *"[WIP] [WIP] [WIP]"* in red,
because nothing existed to actually SPEND the currency, and nothing
displayed the balance correctly either. This pass finishes both halves.

| File | Role |
|---|---|
| `src/Shared/RebirthShopUpgrades.luau` | Definitions, costs, effect math |
| `src/Server/RebirthShopService.server.luau` | Purchase validation, persistence, the 3 gameplay-effect remotes |
| `src/Client/RebirthShopPanel.client.luau` | The panel UI (🔮 button, left edge, under the Sanctum button) |

### Bug fixed: balance never initialized on join

`player:SetAttribute("RebirthCurrency", ...)` was only ever called the
moment a player performed their **next** rebirth that session — a
returning player with an already-large Shard balance saw nothing (Shop
balance reading 0) until they rebirthed again. Same bug shape as the
Sanctum's "stuck showing 0" issue from earlier in this doc. Fixed the same
way: `PlayerDataHandler` now sets the attribute at join from saved data,
and a leaderstat ("Prestige Shards") mirrors it live off an
`AttributeChanged` listener, so every future call site that changes the
balance gets a correct display for free.

### Why five mechanics instead of five more stat lines

The Earth tree and the Shadow Sanctum both already do "flat number goes
up" extremely well. Prestige Shards are far scarcer (1-7 per **rebirth**,
which itself takes a real session) — spending that on a fourth copy of
"+essence %" would waste the one currency in the game that could justify
something weirder. Each of the five below changes HOW a system behaves,
not just its size, and each is driven by a different trigger so they
never compete for the same moment:

| Upgrade | Cost (lvl1→max) | Trigger | Effect |
|---|---|---|---|
| ⚡ Momentum Core | 3→39 (5 lv) | Sustained clicking | Stacking essence bonus per combo stack (up to 20x); pausing 1.2s resets it |
| 🌀 Gravity Well | 5→40 (4 lv) | Timer pulse | Nearby same-type orbs periodically fuse into fewer, bigger ones (+8-20% bonus value) |
| ♊ Twin Ascension | 4→52 (5 lv) | Rebirth itself | Chance (5-28%) for a rebirth to grant DOUBLE Prestige Shards |
| 🌅 Second Wind | 6→29 (3 lv) | Orb energy hits 0 | Instant refill (40-75%) + a burst of 1.5x essence, on its own cooldown |
| 💎 Shard Rain | 8→155 (5 lv) | Any collection | Rare chance (0.4-2%) to also drop 1-2 bonus Prestige Shards |

All five persist through rebirth (`PlayerData.RebirthShopUpgrades`, kept
separate from `Upgrades` for the same reason `SanctumUpgrades` is — a
rebirth wipes the Earth tree, never this).

### Server authority per upgrade

- **Momentum** feeds a real essence multiplier, so the combo count is
  tracked server-side (`OrbClickManager.server.luau`'s `comboState`), not
  trusted from the client. A player attribute (`MomentumStacks`) mirrors
  it out for display and for `EssenceMultiplier` to read.
- **Gravity Well** is pure client visual/gameplay: it only ever combines
  the `EssenceValue` of orbs that already exist and were already going to
  be collected, through the exact same `Collection` remote everything
  else uses. No new trust surface beyond what any single orb already had.
- **Twin Ascension** rolls inside `RebirthHandler.luau`'s `PerformRebirth`
  — a fully server-only transaction already. Deliberately doubles only the
  currency GRANT, never the rebirth count itself: bumping the count by 2
  could let a lucky roll skip clean past a milestone.
- **Second Wind** triggers inside `EssenceOrbController.Fire` (already
  server-authoritative for HP) and reports the trigger back to
  `OrbClickManager.server.luau`, which grants the boost — same
  separation of concerns as `wasTrickle` already used: HP math stays in
  one module, reward orchestration in the other.
- **Shard Rain** rolls in `OrbClickManager.server.luau`'s existing
  collection handler, right where crit/gold already do their own rolls —
  independent odds, since it pays a completely different currency.

Second Wind and Eclipse (the Sanctum relic) both grant their boost via
the *same* `PotionTimerService` effect (`"EssenceX15"`) rather than
registering a second one. That's intentional, not a missed opportunity to
differentiate them: `PotionTimerService` currently has no guard against
two *different* named effects stomping the same `EssenceMultiplier`
attribute on expiry (see the Eclipse section above for the full
reasoning) — reusing the one proven-safe effect sidesteps that gap
entirely. Triggering one while the other is active just extends the
shared timer, which is the correct behavior for two sources of the same
conceptual boost.

### Panel

Near-identical structure to the Sanctum panel (same render / affordability-
pulse / announce-once code shape) but a warm gold/amber "ascension" theme
instead of the Sanctum's cool purple, so the two shops still read as
distinct rooms despite sharing a layout. Button sits at
`UDim2.fromScale(0.895, 0.377)` — one slot below the Sanctum button in the
same manual left-edge column.

### Relic bar gets a 6th member

Gravity Well's countdown also registers into the shared bottom-center
relic bar (`Juice.RegisterRelicPill`, `Order = 5`) even though it isn't a
Sanctum relic — it's still a periodic, automatic, visual ability, and
reusing the bar was the entire point of building it as a shared component.

### Orb cap interaction

`BASE_MAX_ACTIVE_ORBS` (40, see the Sanctum section above) directly
affects how often Gravity Well finds clusters to fuse — more orbs on
screen at once means more chances for same-type orbs to land within
`MergeRadius` of each other. No extra tuning needed for this: the existing
overflow upgrades (Earth tree's `overflow_capacity`, Sanctum's
`sanctum_overflow`) already raise the cap for players who want denser
fields, which now also means more frequent, bigger Gravity Well fusions —
one more reason those upgrades stay worth buying.

---

## 9. Balance pass + the real onboarding fix (this pass)

Two separate asks this time: audit every price in the game against every
other price ("balanced" meaning internally consistent, not necessarily
cheap — this is an incremental game, huge numbers are the point), and fix
the tutorial's collection step, because of everyone who has ever played,
only 427 of 1,260 (34%) have ever collected a single Earth Essence.

### 9a. Why the 66% never-collect number is (almost certainly) a UX bug,
not an economy bug

Traced the actual collection mechanic end to end
(`src/Client/CursorCollection.client.luau`): collecting a drop isn't the
click — it's hovering your cursor over the drop and holding still while a
ring charges (`BASE_CHARGE_TIME`), on a hit-target only `BASE_RING_SIZE`
pixels wide, that moves the whole time (every landed orb idly orbits its
resting spot). Nothing in the game tells you currency only moves on a
*successful hover*, not a click — clicking the great orb LOOKS like it
did something (it visibly shatters, drops fly out, a pop plays), so nobody
gets an error, they just... don't get essence, and don't know why. The
old tutorial's first step described hovering in text but only ever showed
a *scripted* cursor doing it automatically — a player could sit through
the whole tutorial, hit Next five times, and never once have attempted a
real collection themselves. That gap is almost certainly the 66%.

Two fixes, one in each file that actually owns the mechanic:

- **`CursorCollection.client.luau`**: `BASE_RING_SIZE` 20 → 30 and
  `BASE_CHARGE_TIME` 0.5 → 0.4. Same "raise the floor, keep the upgrades
  meaningful" pattern as the section 6 pacing pass — `collection_radius_1/2`
  and `swift_collection_1/2` still add on top of this exactly as before,
  this only makes the very first, un-upgraded attempt more forgiving.
  Couldn't playtest the actual pixel feel (see the Argon syncback warning
  below — the orb template's real on-screen size isn't in this repo), so
  this is a deliberately modest bump, not a redesign.
- **`Tutorial.client.luau`**: the Large Orb step no longer advances on a
  button or a timer. It now watches the player's own `leaderstats` for a
  *real* collection (`Earth Essence` or `Shadow Essence`'s `Quantity`
  attribute increasing — the exact same signal `PlayerDataHandler` reacts
  to, so this can't drift out of sync with what "collected" actually
  means) and only proceeds once that happens for real. Hints escalate at
  14s and 34s if nothing's landed yet, and a fallback "Next" button
  appears at 58s so nobody gets hard-walled — the goal is a forced first
  success, not a wall. Text was also rewritten to lead with the actual
  two-step action ("click... THEN hover and hold") instead of burying
  "hovering" as one word in a longer sentence, and calls out touch input
  explicitly ("press and hold your finger on the drop") since nothing
  previously mentioned mobile at all.

Implementation note: the new watch logic (`startFirstCollectionWatch`)
is defined *before* `TUTORIAL_STEPS`, but needs `dialogueText`/
`nextButton`/`updateProgressDots`, which are built *after* — normal Lua
upvalue scoping would've had it silently close over stray globals. Fixed
by forward-declaring those three as locals near the top of the file and
assigning (never re-declaring with `local`) at their real definition
sites further down.

### 9b. Full Earth-tree cost audit

Wrote a script that computes `BaseCost * CostGrowth^level` summed across
every level for all 49 upgrades, then compared totals within each tier
(same `Tier`, so same rough power band) to find anything wildly out of
line with its siblings. Two things stood out, and only one was a bug:

- `global_multiplier_1`/`global_multiplier_2` ("Essence Affinity I/II")
  cost 10.8M and 2.56B respectively to fully max. **Left alone** — pass 4
  (section above, already in this file) explicitly designed these two as
  late-game control valves specifically so a flat global multiplier can't
  be maxed early and trivialize the rest of the tree. Early levels are
  still cheap (46 and 850 respectively); the escalation is the point.
- `collection_radius_1`/`collection_radius_2` cost 42,079 and 2,259,831 —
  10-20x any other tier-1/tier-2 node **except** the two intentional
  outliers above, with no design note anywhere claiming that was on
  purpose. Root cause: both carry an unusually high `MaxLevel` (20 and 25,
  vs. the usual 8-10 everywhere else in the tree) that survived multiple
  rounds of "multiply every `CostGrowth` by ~1.45x" blanket passes without
  ever being re-checked individually — more levels compounds a flat growth
  rate much harder, and nobody re-derived what growth rate 20-25 levels
  actually needs to land in the same band as everything else. Fixed by
  lowering `CostGrowth` only (1.46 → 1.272, 1.45 → 1.185) — `BaseCost`,
  `MaxLevel`, and `EffectPerLevel` are untouched, so it's still the same
  smooth 20/25-step radius curve, just no longer costing more than
  literally every other upgrade in the game combined to finish.
- Fixed `ascension_insight`'s description, which still had a literal red
  `[WIP] [WIP] [WIP]` tag in it — cosmetic leftover from before the
  Prestige Shop (section 8) actually existed; the system it describes has
  worked since that pass, the text just never got updated to say so.

Everything else — Sanctum costs, Prestige Shop costs, rebirth cost curve,
daily/quest/chest rewards — was re-checked against this same "does it sit
in a sane band relative to its neighbors and to realistic income at that
stage" standard and left alone; no other outliers found.

---

## What to check when you open Studio

1. **Press play and confirm essence actually goes up.** This is the whole
   ballgame. Click the orb, hover a drop, watch the counter. If it moves,
   the core bug is fixed.
2. **Play through the tutorial's first step as a genuinely new player
   would** — don't just click Next. Confirm the step actually waits for a
   real collection and advances itself (with a short celebration) once
   one lands, and that the 14s/34s hints and the 58s fallback Next button
   show up if you deliberately do nothing.
3. **Check the five new buttons** (🎁 Daily / 📜 Quests / 🎟️ Codes /
   🌑 Sanctum / 🔮 Prestige Shop) on the left edge don't overlap your
   existing UI. Positions live in the `LAYOUT` table at the top of
   `ProgressionHud.client.luau`, `SanctumPanel.client.luau` and
   `RebirthShopPanel.client.luau` — one line each, no hunting.
4. **Try a code** (`LAUNCH`) to confirm the redeem flow works end to end.
5. **Watch the Output window** for red errors on join.
6. **Daily panel auto-opens** on a first join once the tutorial is done.
   If you'd rather it didn't, delete the "FIRST-SESSION NUDGE" block at
   the bottom of `ProgressionHud.client.luau`.

## ⚠️ One thing to be careful about

Your Argon syncback only captured instances that **contain scripts**.
Every `.meta.json` in `src/StarterGui` is just `{"className": "..."}` with
no properties, and things like `MainGui.Left` and the `Healthbar` don't
exist in this repo at all.

That means **this repo is not a complete copy of your UI.** If you ever
sync in the filesystem→Studio direction with "filesystem wins", you could
wipe UI that only exists in Studio. Sync Studio→filesystem, or keep using
the two-way sync with Studio as the source of truth for UI.

If you want the repo to hold your real UI too, turn on property syncback
in Argon's settings and re-sync — worth doing, since right now the repo
couldn't rebuild your game from scratch.

## Not done deliberately

The loading screen's horror/ARG tone (screen shake, whispered "i see
you", jump-scare eyes) clashes hard with the bright, cheerful tutorial
and mascot that follow it, and it delays first play. I left it alone —
it's clearly deliberate creative work and that's your call, not a bug.
Worth deciding on though: it's the first thing every new player sees.
