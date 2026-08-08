# What changed, and what to check in Studio

Two commits on `claude/retention-and-captivation`. Everything below is
either a bug fix to existing code or a self-contained new file — no
existing gameplay system was restructured.

---

## ⚠️⚠️ 0. THREE PAID GAMEPASSES DO NOTHING -- READ THIS FIRST

Found while reading `ProductPurchaseHandler.server.luau` for unrelated
reasons. **Deliberately not fixed this pass** -- this is a real-money,
business-facing decision (what should a paid feature actually do, at the
price it's already listed at, for players who may have already bought
it), not a balance/engagement call I should make unilaterally the way
everything else in this doc was.

Three Game Passes take a real player's real Robux, set a flag
(`data.Gamepasses[id].Owned = true` and a matching player Attribute),
and then **nothing else in the entire codebase ever reads that flag**.
Grepped every one of these IDs across `src/` to confirm -- zero other
references, in any file:

| Game Pass | Id | What it currently does |
|---|---|---|
| Lucky Finder (+50% Luck) | `1907239833` | Sets a flag. Nothing reads it. |
| Ultra Luck (+300%) | `1906063939` | Sets a flag. Nothing reads it. |
| Dedicated Essence | `1907077899` | Sets a flag. Nothing reads it. |

For comparison, the other four Game Passes in the same file all DO
something real: VIP Rank (`1909291891`) gives a gold name/icon outline
(`UIInitializerHooks.client.luau`), 2x Essence Multiplier (`1907605899`)
is read in `EssenceMultiplier.CalculateMultiplier`, Auto Absorption
(`1907677938`) is read in `CursorCollection.client.luau`'s collection
loop, and Material Alchemist (`1907863864`) doubles the offline-earnings
base rate in `IdleService.server.luau`. Only these three "Luck"/
"Dedicated Essence" ones are stubs.

**Why I didn't just implement something:** "Luck" could plausibly mean
crit chance, golden-storm chance, essence rarity odds, or something else
entirely -- and whatever it's priced at was presumably priced against
SOME intended effect size. Guessing wrong either shortchanges someone
who already paid for it, or accidentally breaks the economy balance this
whole pass spent a lot of care on. That's a decision for whoever set the
price and wrote "Luck" and "Dedicated Essence" on the store listing, not
something to invent from a variable name.

**What actually needs to happen:** decide what each pass should do, then
wire it into the relevant system the same way the four working passes
already do it (an attribute check + a multiplier/bonus in the right
place). If any of these three has already been purchased by a real
player, that's also worth knowing before deciding what "fixing" it even
means (does it retroactively start working now that a system exists for
it, or does the definition just get written and apply going forward).

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

## 10. Global Leaderboards (Top Essence / Top Rebirths)

Started an open-ended "keep adding engagement systems" pass. First up:
the game had zero social comparison anywhere -- no leaderboard, no rank,
nothing to compare yourself against another player with. That's one of
the strongest retention levers an incremental game can have and it was
entirely missing.

**`src/Server/LeaderboardService.server.luau`** (new) owns two
`OrderedDataStore`s -- `EssenceLeaderboard` (lifetime `TotalEssenceGathered`,
both essence types combined) and `RebirthsLeaderboard`. Deliberately
conservative on DataStore budget since this is a pure social/cosmetic
feature that must never risk anything else:

- Each online player's own score is written **at most once every 60s**,
  and only if it actually changed -- the server does the writing
  (`SetAsync(tostring(player.UserId), value)`), never the client.
- The top 50 of each board is re-read (`GetSortedAsync`) and broadcast to
  every online client **once every 3 minutes**, not per-request -- nobody
  polls the store themselves, so DataStore load stays flat regardless of
  player count.
- Player names are resolved from UserIds via `GetNameFromUserIdAsync` and
  cached in memory, so a player sitting in the top 50 across multiple
  refreshes doesn't cost a repeat name lookup.
- Every DataStore call is `pcall`-wrapped with a `warn` on failure and a
  silent no-op otherwise -- if DataStoreService is unavailable (Studio
  without "Enable Studio Access to API Services" on), the leaderboards
  are just empty, nothing else in the game is affected.

**`src/Client/LeaderboardPanel.client.luau`** (new) is a pure viewer, same
contract as Sanctum/Prestige Shop: draws whatever the server last
broadcast, computes nothing itself. New 🏆 "RANKS" button at
`(0.895, 0.377)` -- the exact slot the Prestige Shop button occupied
before it was manually moved to `(0.895, 0.213)`, so it's already proven
not to collide with anything on that column. Tabs for each board, top 3
get medal icons, your own row is gold-highlighted with a ★ if you're in
the visible top 50, and a quiet "not in the Top 50 yet" note if you
aren't -- deliberately doesn't claim an exact rank outside the cached top
50, since computing that would mean an expensive full-store scan for
something that isn't worth the DataStore cost.

**Follow-up, same pass: added a third board, "This Week."** A
lifetime-only leaderboard is a wall for anyone who didn't start on day
one -- a new player can never out-earn a veteran's total no matter how
well they play right now, which discourages exactly the players who'd
benefit most from a reason to compete. "This Week" tracks essence gained
since each player's own weekly baseline (`WeeklyBaselineValue`/
`WeeklyBaselineWeekNumber` on PlayerData, reset automatically the moment
the current UTC week number moves past what's stored) and writes to a
WEEK-NUMBERED store name (`WeeklyEssenceLeaderboard_W<n>`) instead of a
fixed one -- a new week is simply a brand new, empty store, so there's no
expiry/cleanup job to write or forget to run. Everything else (the
write-throttle, the broadcast cadence, the pcall-everything safety net)
is shared with the other two boards, not a parallel implementation.

## 11. Achievements panel (Badges finally have somewhere to live)

The 13 Roblox badges this game already awards (BadgeService toast only,
zero in-game visibility -- no way to see which exist, which you have, or
what's left) plus a new set of in-game **Milestones** with real claimable
rewards, since a checklist with no payoff is a weaker hook than one with
an actual "claim +2,000 essence" button at the end of it.

**`src/Shared/AchievementsConfig.luau`** (new) is pure data, same
contract as every other `*Config`/`*Upgrades` module: the 13 badges (name/
icon/description reconstructed by grepping every `BS:AwardBadgeAsync`
call site in the codebase to find what actually triggers each one -- see
the file's own comment block for the full map) plus 10 new Milestones.
Every Milestone's trigger stat (`TotalEssenceGathered`, `CriticalEssence`,
`Rebirths`, `ManualStormsSummoned`, `UniqueEssences`, `PlayTime`) is one
that's already tracked, server-owned, and monotonic (never decreases),
which is what makes it safe for a milestone to stay "complete" forever
once crossed -- none of them key off RebirthCurrency's current balance,
since that one's spendable and would let a milestone un-complete itself.
(`PlayTime` was added in a follow-up to this section, once its update
cadence was confirmed -- it only actually increments on a save cycle,
leave or the 120s autosave, not continuously, so that one milestone's
progress bar moves in ~2-minute steps rather than live. Fine at a 3-hour
target.)

The two Hollowed-ARG badges ("It Has Noticed You" / "Nothing Left
Hidden") are marked `Secret = true` and rendered as "???" until earned --
that content is deliberately mysterious (see the loading screen's horror
tone, described elsewhere in this doc) and a public achievements list
describing them up front would spoil it.

Reward amounts were sized against the same tree-cost bands from the
balance pass (section 9): 150-25,000 essence for the essence-reward
milestones, 1-3 Prestige Shards for the rebirth-count ones, small enough
to feel like a nice bonus for a goal you were already chasing rather than
a way to skip the economy.

**`src/Server/AchievementsService.server.luau`** (new) re-derives badge/
milestone completion from server-owned stats on every claim request --
the client can only ask, never claim for itself. Rewards pay out through
the SAME paths every other grant in the game already uses (the Earth
Essence leaderstat's `Quantity` attribute; `RebirthCurrency` for Shards),
so there's exactly one source of truth for each currency, not a second
one this file invented. Pushes a fresh sync to every online player every
5 seconds (cheap -- pure in-memory reads, no DataStore calls) so progress
bars creep forward live while the panel is open.

**`src/Client/AchievementsPanel.client.luau`** (new) is the one panel
this pass where rows are built ONCE and only ever have their properties
**updated** on sync, never destroyed and rebuilt -- with a sync landing
every 5 seconds, rebuilding ~22 instances each time would flicker and
reset the scroll position out from under anyone with the panel open.
New 🏅 "GOALS" button at `(0.895, 0.459)`, continuing the 0.082-apart
rhythm the left-edge column already established (Prestige Shop 0.213 →
Sanctum 0.295 → Leaderboard 0.377 → this one). Same affordability-badge
pattern as Sanctum's "!" pip, but for "you have something to claim"
instead of "you can afford something."

## 12. Two more celebration moments

Checked whether "celebrate crossing a big number" already existed before
building anything -- it did, for essence balance (`UIManagement.client.luau`'s
`celebrateMilestone`, thresholds 100 through 1e14) and for rebirths in
general (`RebirthEffect.luau`'s full-screen sequence, already fires on
every single rebirth). Two real gaps were left:

- **Badges had zero celebration beyond Roblox's own small, easy-to-miss
  toast.** New `src/Client/BadgeCelebration.client.luau` watches the same
  per-badge player Attributes every grant site already sets (see
  AchievementsConfig's comment block for the full map) and plays a full
  Ring/Burst/FloatText/sound moment the instant one flips to earned --
  purely client-side, reads nothing it doesn't already trust. Has the same
  join-time settle guard as the existing essence-milestone system (4
  second grace window before it starts watching) so a returning player
  with several badges already earned doesn't get every single one
  replayed at them on login.
- **Milestone rebirths (1/5/10/25/50, see RebirthHandler's MILESTONES
  table) got the exact same effect as an ordinary rebirth**, despite
  granting a permanent bonus on top of the normal one. Added
  `celebrateMilestoneIfAny` to `RebirthUIManagement.client.luau`, firing
  a second, bigger banner ("⭐ MILESTONE: Ascended" + its description)
  right after the existing RebirthEffect finishes rather than competing
  with it -- so an ordinary rebirth is unchanged and a milestone one gets
  something extra on top.

## 13. Essence Rush -- the first server-wide timed event

Every existing timed boost in the game (Second Wind, Daily Day 7,
Playtime chests, Shadow Eclipse) is personal -- it happens to YOU,
whenever your own progress happens to trigger it. Nothing ever happened
to the whole server at once, which is a specific, well-known retention
lever ("something's happening right now, everyone's in on it") this game
had zero of.

**`src/Server/EssenceRushService.server.luau`** (new) fires roughly every
20-35 minutes (randomized so it doesn't read as a predictable metronome),
giving EVERY currently-online player a 4-minute 1.5x essence boost at the
same moment. Reuses the exact same `"EssenceX15"` PotionTimerService
effect every other temporary boost in the game already shares -- this is
a deliberate, previously-established rule (see the Shadow Eclipse /
Second Wind sections above): two differently-named effects both writing
the shared `EssenceMultiplier` attribute could clobber each other, so
anything granting a temporary essence multiplier reuses this one name. A
player who joins mid-Rush still gets whatever time is left rather than
missing out purely on bad timing.

**`src/Client/EssenceRushBanner.client.luau`** (new) gives the moment two
things the existing generic Potion Timer HUD card doesn't: an arrival
flourish (same Flash/FloatText/sound language the Essence Storm
announcement already established) framing it as a real event, and a
persistent top-of-screen banner with its own live countdown for the
whole 4 minutes -- positioned at `0.155` scale specifically to clear the
`0.055-0.14` zone `ProgressionHud`'s own reward toast uses, so the two
can't collide if a daily/quest toast happens to land during a Rush. The
existing small potion card at the bottom of the screen will still show
too (it's the same underlying effect) -- that's fine, the two serve
different purposes: one is the ongoing personal status indicator every
other potion already uses, the other is "this is a shared event
happening for everyone right now."

## 14. Comeback bonus for genuinely lapsed players

Traced the existing offline-earnings system (`IdleService.server.luau`)
before touching anything, and it's more complete than it first looked:
every player gets a baseline 10% offline rate (50% with the "Material
Alchemist" gamepass) even with zero `offline_harvest` upgrades, computed
from each essence's `savedEPM` (tracked by `EPMService`/
`PlayerDataHandler`'s save cycle). Not broken. But it caps at
`OFFLINE_HARVEST_CAP_SECONDS` (8 hours) -- correctly, so idling can't
out-earn active play -- which means an 8-hour absence and a 3-week
absence produce the EXACT same "Welcome Back" popup. Nothing ever
acknowledged that someone who genuinely lapsed came back.

Added a separate, flat **Comeback Bonus** in the same file, gated on the
UNCAPPED real time away (not the 8-hour-clamped value the earnings math
uses): 300 essence at 1+ day, 1,200 at 3+, 3,500 at 7+, 8,000 at 14+,
each scaled by rebirths via `ProgressionConfig.ScaleReward` (the same
scaling daily rewards and quests already use, so it stays meaningful for
veterans instead of trivial). Folded into the SAME reward table the
existing "WELCOME BACK!" popup already displays (as a
`"🎉 Welcome Back Bonus"` line) rather than building a second, competing
UI -- the emoji-prefixed key also happens to sort after the real essence
names alphabetically, so it lands at the bottom of the list, reading as
a bonus tacked onto the regular earnings rather than mixed in with them.

## 15. Fixed a crash in the Earth tree purchase handler

`UpgradeEvent.server.luau` pre-checked every purchase with
`TreeModule.CanAfford(data, TreeModule.GetCostForNextLevel(name, ...))`
before ever calling `PurchaseUpgrade`. `GetCostForNextLevel` only returns
`nil` for a genuinely unknown upgrade id (it doesn't check `MaxLevel` at
all), and `CanAfford` does `for currency, amount in pairs(cost)` with no
guard on `cost` itself -- so any malformed/unknown `name` from the client
(a stale id from a renamed upgrade, or a direct/malformed remote call)
crashed the handler with a bare `pairs(nil)` error before it ever reached
`PurchaseUpgrade`, which already checks unknown-id/locked/maxed correctly
and returns `false, reason` instead of erroring. Simplified to just call
`PurchaseUpgrade` directly and trust its return value -- it was already
the correct single source of truth, the pre-check was both redundant and
the one place actually missing a guard.

Same audit turned up a second, related crash on the CLIENT side:
`UpgradeUIManagement.client.luau`'s `BuyRemote.OnClientEvent` handler did
`local child = frame:FindFirstChild(upgradeName); child:SetAttribute(...)`
-- with the `if not child then return end` guard sitting on the line
*after* the SetAttribute call it was supposed to protect, i.e. after the
crash it was meant to prevent. Reordered so the check actually runs
first. Server-side, `upgradeName` is now always a real, valid tree
upgrade id (see the fix above), so this is defense in depth rather than
the primary fix -- but the comment directly above the buggy line
literally said "Safely find the main child," so it's worth having the
code actually do that.

Kept reading the same file (it's the whole Upgrades tree's UI
controller) and found two more things worth fixing:

- **Dead duplicate code.** `isDragging`/`lastInputPos` were declared
  TWICE near the top, with a full `viewport.InputBegan` handler wired to
  each. Lua's `local` shadows rather than reassigns, so the first
  declaration and its handler were provably disconnected from everything
  else in the file (confirmed via the scoping before touching it, not
  guessed) -- pure dead code, removed.
- **`for index, IndexData in tree do` is missing `pairs`/`ipairs`.**
  `tree` is a plain array table (`TreeUpgrades.GetVisibleTree` builds it
  with `table.insert`, no metatable), and Lua's generic `for` loop needs
  an actual iterator function in that slot -- calling a table value
  errors immediately. **This function (`onRebirth(false)`) runs
  unconditionally at the bottom of the script**, so as committed in this
  repo, this would fire the instant the Upgrades popup's script loads,
  for every player, every session. I can't confirm from here whether
  this exact line is what's actually live in Studio right now (per the
  Argon syncback warning elsewhere in this doc, this repo isn't
  guaranteed to be a perfect mirror of what's deployed) -- but the fix
  (`ipairs(tree)`) is unambiguously correct Lua and safe to apply
  regardless of which case it turns out to be: if this was live-broken,
  it's now fixed; if Studio already had a working version, this just
  makes the repo match it. **Worth an explicit test in Studio** given
  the severity if it was real: open the Upgrades tree and confirm it
  populates/updates at all.

## 16. "What's New" popup (so all of the above actually gets discovered)

Everything in sections 10-14 (leaderboards, achievements, Essence Rush, the
comeback bonus) shipped purely additively -- nothing in-game ever told an
existing player any of it showed up. Someone who played before this pass
would come back to a handful of new side-buttons and zero explanation. This
is the fix.

**`WhatsNewConfig.luau`** (`ReplicatedStorage`) is pure data: a
`CurrentVersion` number plus a short `Highlights` list (icon + one-line
description each). To announce something new later, bump `CurrentVersion`
and replace `Highlights` -- there's no history log, a player who's several
versions behind just gets caught up with the latest list in one popup
rather than replaying a stack of old ones.

**`WhatsNewPopup.client.luau`** builds a small closable modal (same
build-in-code + THEME pattern as `ProgressionHud`/`AchievementsPanel`) and
shows it once per version bump. Closing it any way (the CTA button, the X,
the backdrop, Escape) marks it seen via the same `UpdateData` remote every
other `Seen*` flag already uses (`SeenWhatsNewVersion`, added to
`UpdateData`'s `ALLOWED_ROOTS` allowlist and `DefaultPlayerData`, mirrored
to a player attribute in `PlayerDataHandler` next to `SeenFavoritePrompt`)
-- there's no reward to gate, it's pure announcement.

**Deliberately never shown on a player's first-ever session.** "What's
New" implies "since you last played," which is confusing framing for
someone who's never played, and would stack a third automatic popup on top
of the tutorial and `ProgressionHud`'s first-session Daily nudge. The
script reads `SeenTutorial` the moment it first appears -- which
`PlayerDataHandler` sets from the *saved* value at join, before
`Tutorial.client`'s own logic runs -- so the first value observed is
whatever it was before this session started. `false` means this is their
first-ever session (popup skipped entirely, this session only); `true`
means they've played before (gate passes). Next time a truly-new player
joins, `SeenTutorial` is `true` from having finished it, so they catch the
popup then -- exactly the "welcome back, here's what you missed" moment
this exists for.

Doesn't perfectly sequence against `ProgressionHud`'s Daily nudge or the
offline-earnings popup (no central popup queue exists in this codebase to
coordinate that) -- it just waits noticeably longer (6s vs. Progression's
~2s) before showing itself, so on the rare join where more than one
auto-popup is pending, this one tends to land after, not simultaneously.
Given it only fires once per version bump, occasional overlap is a minor
cosmetic risk, not a broken experience.

## 17. Fixed a real button collision, added an (inert until configured) Group Reward

**The bug.** While picking a screen position for a new button (below),
I checked every existing right-edge button's coordinates against each
other for the first time this session and found a real one:
`ProgressionHud.client.luau`'s Daily/Quests/Codes stack was built at
`x=0.92`, centered at `y=0.2`, rendering roughly `y=0.09..0.32`.
`RebirthShopPanel.client.luau`'s button sits at `(0.895, 0.213)` and
`SanctumPanel.client.luau`'s at `(0.895, 0.295)` -- a different column,
but only `0.025` away in x against `0.062`-wide buttons, so the two
columns overlapped in **both** axes across two of the four buttons.
None of these are gated behind rebirth count or anything else -- all
four are visible from a player's very first session, so this wasn't an
edge case. Fixed by moving `ProgressionHud`'s stack down to `y=0.63`,
clear of the whole Sanctum/Prestige Shop/Leaderboard/Achievements
column (which bottoms out around `0.49-0.51`) -- one line, one file,
rather than renumbering four already-shipped buttons for one collision.
**I can't render Roblox UI from here, so this was fixed from source
math, not a screenshot** -- please eyeball it in Studio (checklist item
3 below).

**The new feature.** `GroupRewardConfig.luau` + `GroupRewardService.
server.luau` + `GroupRewardPrompt.client.luau` add a standard, free,
permanent essence bonus (+10% by default) for players who've joined the
game's Roblox group -- unlike a gamepass, group membership actively
helps the game itself (shouts, wall posts reach every member). Checked
once per join server-side (`Player:IsInGroup`, cached to a `GroupMember`
attribute so `EssenceMultiplier.CalculateMultiplier` -- which runs on
every single collection -- never makes a live API call) and folded into
the multiplier stack the same way every other bonus in that function
already works. The client button (👥, +N% shown live from config) opens
the group's page via `GuiService:OpenBrowserWindowAsync` and disappears
once the player is actually a member.

**Ships fully inert:** `GroupRewardConfig.GroupId` defaults to `0`,
which every piece of this feature treats as "disabled" -- no API calls,
no attribute, no button. This is a different situation from the three
non-functional gamepasses flagged in section 0: those needed an actual
product decision I can't make (what should "Lucky Finder" *do*?); this
one's design is just the genre standard, and the only missing piece is
a literal id copy-pasted from the group's own URL. **To turn it on,
set `GroupRewardConfig.GroupId` to your real group id** -- that's the
entire setup step.

## 18. Fixed a purchase-crashing nil in ProductPurchaseHandler

Continued the file-by-file audit into `ProductPurchaseHandler.server.
luau` -- carefully, since this is the one file in the codebase this
pass has consistently treated as higher-risk (real money), and the fix
below is deliberately a pure crash-prevention change, not a pricing or
design decision (same bar that kept this pass from guessing at the
three non-functional gamepasses in section 0).

Both Time Warp developer products (`3609555620` / `3609555653`) call
`EPMService.getEPM(player)` and immediately `for name, Quantity in
pairs(EPMS) do`. `getEPM` returns a bare `nil` -- not an empty table --
whenever `EPMService.ActiveSessions` has no entry for that player yet
(the "Absolute fallback" case in that file), which is a real
reachable state: `PlayerDataHandler` populates `ActiveSessions` during
its own join sequence, and `ProcessReceipt` can in principle fire
before that's finished (a receipt that was already pending when the
player rejoined, for instance). `pairs(nil)` throws immediately in
that case, taking a *paid* purchase down with it.

This codebase's own docstring for this file explains why that matters
specifically here: Developer Products are supposed to keep retrying
via `ProcessReceipt` until the handler cleanly returns a decision --
that retry guarantee is what the Essence Rain handler already relies
on a few lines up (`return false` deliberately, so Roblox tries again
later instead of the storm silently eating the charge). An uncaught
error is not the same as a clean `return false` and isn't a reliable
way to get that retry -- so this crash risked the exact "took the
Robux, granted nothing, and isn't guaranteed to retry" failure mode
the rest of this file is deliberately careful to avoid. Fixed by
guarding both handlers with the same "no session yet -> return false"
pattern already established for the storm purchase.

## 19. Closed a real "claim any badge instantly" exploit

`GrantBadge.server.luau` is a tiny, generic RemoteEvent handler:
whatever badge id the client sends, it sets the matching attribute,
writes `PlayerData.Badges[id] = true`, and calls Roblox's real
`BadgeService:AwardBadgeAsync` for it. **It had no validation on that
id at all.** Any client -- not just the legitimate caller -- could
`FireServer` with any of this game's 13 badge ids (all listed in
`AchievementsConfig.Badges`, which is in `ReplicatedStorage` and
therefore fully readable by an exploit) and be instantly, permanently
awarded that badge, including the two secret Hollowed One ARG badges
that are supposed to require reaching real essence milestones
(1,000 / 10,000,000 essence) through actual play.

The only legitimate caller is `TheHollowGlitch.client.luau`, and it
only ever asks for exactly two ids -- the secret badges, fired the
moment its own client-side lore event reaches Tier 1 / Tier 6. Every
other badge (First Steps, Essence Baron, Storm Caller, ...) is awarded
by direct server-side calls elsewhere (e.g. `RebirthHandler.server.
luau` awards the rebirth badges inline, never through this remote) --
so this generic remote was never *supposed* to be able to grant
anything but those two.

Fixed with an explicit allowlist of exactly those two ids; anything
else is rejected and logged. This doesn't re-verify the essence
threshold server-side (that would mean duplicating
`TheHollowGlitch.client.luau`'s own eligibility logic, which reads
lifetime vs. current essence in a way I didn't want to guess at and
risk blocking a legitimate player) -- so a forged call can still claim
one of these two specific badges a little early. What it closes is the
much bigger hole: claiming literally any badge in the game, on demand,
with zero validation.

**Related, smaller fix in the same file:** every other `AwardBadgeAsync`
call in this codebase (`StormController.luau`, `RebirthHandler.server.
luau`) passes the badge id as a NUMBER, matching `DefaultPlayerData.
Badges`' own numeric keys -- `GrantBadge.server.luau` was the only one
using the raw STRING the client sent, which would write a separate,
string-keyed entry into `PlayerData.Badges` instead of updating the
real numeric-keyed default. `tonumber()`'d before the `Badges[...]`
write and the `AwardBadgeAsync` call now (the `SetAttribute` call
correctly keeps the string -- Roblox attribute names must be strings
regardless of what the id conceptually is).

Also removed a `print(playerData)` left in `StormController.luau`'s
`_startStorm` -- harmless, but it fires on every single storm
(automatic, manual, and purchased), so it was real console spam in a
live server.

## 20. Audited every OnServerEvent/OnServerInvoke handler in the codebase

After fixing GrantBadge's exploit (section 19), the obvious follow-up
question was "is that the only one?" -- so every remote handler in the
game got checked against the same bar: does it trust anything from the
client it shouldn't?

All 13 files with a server-side remote handler:

- `GrantBadge.server.luau` -- fixed (section 19)
- `ProductPurchaseHandler.server.luau` -- fixed (section 18); the
  `ProcessReceipt`/gamepass handlers themselves only ever receive
  Roblox-verified purchase data, not arbitrary client input
- `PotionTimerService.luau` -- fixed (section 17, the remote-folder
  crash); `ApplyPotion` is only ever called from other SERVER scripts,
  never exposed to the client directly
- `UpdateData.server.luau` -- already correct: an explicit
  `ALLOWED_ROOTS` allowlist gates which PlayerData keys a client can
  touch at all
- `UpgradeEvent.server.luau` -- fixed earlier this pass (type check +
  trusting `PurchaseUpgrade`'s own validation)
- `AchievementsService.server.luau`, `OrbClickManager.server.luau`,
  `RebirthShopService.server.luau`, `SanctumService.server.luau`,
  `ProgressionService.server.luau` -- all independently re-derive
  level/cost/balance from server state and never trust a client-sent
  number; RebirthShopService and SanctumService in particular are
  excellent references for this pattern (debounced, type-checked,
  re-validated against server data, never trusting a submitted price)
- `RebirthHandler.server.luau`, `StormInitServer.server.luau` -- take
  no client arguments at all beyond the implicit player, so there's no
  forgeable input surface to begin with
- `ReturnDataToClient.server.luau` -- read-only (returns the caller's
  own PlayerData, nothing else), no validation needed; removed a
  `print(data)` that fired on every single request (this remote gets
  polled every 60s per client by `UIManagement.client.luau`, so it was
  real, frequent console spam)

Net result: one real vulnerability (GrantBadge), one debug-print
cleanup here plus the one already fixed in `StormController.luau`
(section 19), everything else already correct.

## 21. Fixed the offline-earnings popup miscounting the comeback bonus

`RecieveOfflineEarning.client.luau` was written when every key in the
reward table it receives was a real essence type, and it says so:
"You earned N essence types while away". Section 14's comeback bonus
(`IdleService.server.luau`'s `GrantOfflineEarnings`) folds a
`"🎉 Welcome Back Bonus"` entry into that exact same table so it could
reuse this popup rather than needing its own -- which means a lapsed
player claiming their comeback bonus alongside real essence would see
something like "You earned 3 essence types while away" when only 1-2
of those were actually essence. No crash risk (the icon-color lookup
already falls back to a default for an unrecognized name, and Lua's
`string.lower` just passes non-ASCII bytes like the emoji through
unchanged) -- just a small, real, factually wrong line of copy on a
moment that's specifically meant to feel good. Changed "essence type"
to "reward", which reads naturally and is correct regardless of what's
actually in the table.

## 22. Fixed a hard game-breaking risk in the loading screen

`LoadingScreen.client.luau` is the one script every player has to get
through before they can play at all -- so it deserved a check despite
being 1700+ lines of intentionally-stylized horror/glitch effects
(see "Not done deliberately" below). Found this near the top:

```lua
local sounds = game:GetService("SoundService"):WaitForChild("SFX"):WaitForChild("GlitchSounds")
local glitchSound1 = sounds:WaitForChild("Sound1")
```

Bare `WaitForChild`, no timeout, running at the TOP LEVEL of the
script -- not inside the `task.spawn` a few lines below it. That means
it blocks every single line after it, for every player, until
`SFX/GlitchSounds/Sound1/2/3` all exist. If any one of those five
instances were ever missing or renamed in Studio -- an easy mistake,
especially since this repo's Argon syncback doesn't even show these
sound assets exist, so there's nothing here warning a future edit
would break them -- **every player would hang on the loading screen
forever**, with no error in the output and no way to fix it without a
redeploy. That's the single highest-consequence place in the entire
codebase for a fragile asset lookup to live, since it gates 100% of
play, not just one feature.

(Given the game already has real players, this almost certainly isn't
currently happening -- if it were, nobody could have ever gotten in.
But "probably fine today" isn't the same as "safe," and this is
exactly the failure mode every other defensive lookup in this codebase
this pass already guards against, just never applied here.)

Fixed with a timed lookup (5s, falling back to `nil` rather than
hanging) plus a `safePlay(sound)` helper -- all 15 existing call sites
across the file called `glitchSound1:Play()` etc. unconditionally, so
swapping the lookup alone would have just moved the crash to whichever
of those fired first instead of fixing it. A missing sound now costs
only that one glitch effect's audio, never the ability to load into
the game.

**A second, more severe instance of the exact same bug turned up right
after fixing the first one.** Near the bottom of the same file:

```lua
local ready = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("LoadingDone")
```

Same problem (bare, untimed, blocking) -- but `LoadingDone` isn't a
sound effect. It's the BindableEvent this script fires
(`ready:Fire("Done")`) to tell every OTHER script that loading has
finished. Four separate files -- `SoundController.client.luau`,
`TheHollowGlitch.client.luau`, `Tutorial.client.luau`, and
`UpgradeUIManagement.client.luau` -- each independently `WaitForChild`
this exact same instance, also with no timeout, also with no fallback
anywhere in the codebase. If it were ever missing, potentially **all
five scripts** would hang forever, not just this one: no music, no
Hollowed One ARG system, no tutorial, no Upgrades tree UI, and no way
past the loading screen to begin with.

Fixed by making this script -- the one that actually fires the event,
so the natural owner -- create it (and its parent `Remotes` folder) if
missing, as the very first thing it does after grabbing `PlayerGui`,
before any of the loading screen's own setup runs. The other four
scripts' existing `WaitForChild` calls need no changes: as long as
this one reliably creates the instance early, their waits resolve
immediately regardless of which script happens to start first --
`WaitForChild` blocks until an instance appears, it doesn't matter
which script created it or in what order the scripts started.

## 23. The most severe finding this pass: a hang risk that could have silently disabled every purchase in the game

While checking the Shop UI (`ShopUITweens.client.luau`, under
`src/StarterGui`) for how it talks to `ProductPurchaseHandler.server.
luau`, the same "bare WaitForChild, no fallback" bug class turned up
twice more in that file -- and one of them is arguably the worst thing
this whole pass found, worse than the loading-screen ones.

```lua
local sound = game:GetService("SoundService"):WaitForChild("SFX"):WaitForChild("UI"):WaitForChild("RobuxPurchase")
-------------------------------------------------------------------
-- 2) GAME PASS PURCHASE HANDLING
-------------------------------------------------------------------
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
```

This lookup for a purchase-confirmation sound effect sits **before**
`MarketplaceService.ProcessReceipt` gets assigned further down the same
script, and before `PromptGamePassPurchaseFinished` gets connected. If
`SFX/UI/RobuxPurchase` were ever missing or renamed in Studio, this
would hang here forever -- and since Lua runs a script's top level in
order, NONE of the purchase-granting logic below it would ever get
wired up. Not "this one sound doesn't play" -- **every gamepass and
every developer product in the entire game would silently stop
working**, for as long as the server ran, with nothing in the output
to explain why. Whether Roblox holds unprocessed receipts for a retry
once a server eventually restarts with a fixed script is not something
I want to bet real purchases on finding out.

Fixed with the same timed-lookup + `safePlaySound()` guard pattern as
the loading screen sounds (section 22) -- a missing sound now costs
only that one sound effect, never the game's ability to process a
single purchase.

**Second, smaller finding in the same file:** further down, the
RemoteEvent that lets the Shop UI trigger a purchase prompt
(`ReplicatedStorage.Remotes.RequestPurchase`) was also looked up with
a bare `FindFirstChild` and no creation fallback, immediately followed
by `.OnServerEvent:Connect(...)` on the result. This one sits AFTER
`ProcessReceipt` is assigned, so a crash here wouldn't have broken
real purchase granting -- but it would have silently broken the Shop
UI's ability to ever open a purchase prompt at all. Fixed with the
same `ensureRemote`-style fallback used everywhere else in this
codebase.

**Scope note, so this doesn't oversell itself:** there are roughly 326
bare/untimed `WaitForChild(` calls across this codebase in total --
nowhere near all of them have been individually audited. What this
pass specifically targeted was the highest-consequence category: a
lookup sitting at the top level of a script that gates something
critical for every player (loading in at all; every purchase in the
game) before anything else in that script gets wired up. Those two
scripts (`LoadingScreen.client.luau`, `ProductPurchaseHandler.server.
luau`) are now clean of that specific failure mode. The bulk of the
326 are almost certainly fine -- `WaitForChild("PlayerGui")`,
`WaitForChild("PlayerData")` and similar fundamental/always-present
lookups appear dozens of times each -- but "almost certainly fine"
isn't the same as verified, and a full pass wasn't attempted here.

## 24. Prestige Aura -- wearing rebirth status, not just tracking it

Rebirths already unlock real content (`RebirthHandler.luau`'s
`MILESTONES`: new upgrade routes, the Prestige Shop, the Infinity
Core), but nothing about having reached one was ever visible after the
moment it happened -- a player with 40 rebirths looked identical, at a
glance, to one with 1. `PrestigeAura.client.luau` fixes that with a
persistent, ambient visual around the great orb that grows with every
milestone: a soft glow that gets more layered and colorful, then an
orbiting glyph ring from "Ascended" (10 rebirths) up. Crossing into a
new tier plays a real moment -- a burst, a "✨ TIER NAME ✨" float-text,
and a punch -- everything else in this codebase already uses for a
milestone that matters.

**Tier thresholds and names are read from `RebirthModule.
GetMilestoneThresholds()` / `GetMilestone()`** -- a small, safe
addition to `RebirthHandler.luau` (a sorted list of `MILESTONES`' own
keys) -- rather than a second, hand-maintained copy of `1/5/10/25/50`
living in the aura script. If the milestones ever change, the aura
follows automatically, with zero risk of drifting out of sync.

Purely a client-side visual: reads the player's own already-
server-authoritative `Rebirths` attribute and never grants, requests,
or assumes anything. Deleting this script changes nothing about the
economy.

**Three real bugs caught and fixed during my own review before this
ever got committed**, worth naming since they're all a good reminder
that "looks plausible" and "is correct" aren't the same thing:

1. A garbled leftover expression in the celebration text
   (`(x).."!":upper() and (...)`) from composing the string in one
   pass and not cleaning up after changing my mind mid-expression --
   possibly not even a syntax error, just deeply confusing and
   fragile. Rewritten as a plain local variable.
2. The ambient "breathing pulse" read `disc.BackgroundTransparency`
   as its own baseline whenever a cached `BaseTransparency` attribute
   was missing -- but nothing ever SET that attribute, so it always
   fell back to reading last frame's OUTPUT as this frame's baseline.
   Since the pulse can only ever push transparency up, never down,
   this would have compounded every single frame until the outer
   glow layer settled at fully invisible within minutes and never
   recovered. Fixed by actually caching the true base value once,
   in `applyTier`, and having the pulse loop only ever read that.
3. The tier-up celebration punched `Juice.GetScale(LargeOrb)` --
   but `GetScale` finds-or-creates via `FindFirstChildOfClass`, and
   `LargeOrb` already has its own `UIScale` that `OrbClicker.client.
   luau`'s click/hover feedback animates constantly. Punching that
   shared instance would have fought those tweens on the single
   most-clicked element in the entire game. Fixed to punch the aura's
   own holder instead, which owns no UIScale anywhere else.

A fourth issue was a design gap rather than a bug: the aura's
`AnchorPoint`/`Position` were originally hardcoded to `(0.5, 0.5)` on
the assumption `LargeOrb` is center-anchored -- a guess this repo can't
actually verify, since Argon syncback doesn't capture UI property
values. Changed to copy `LargeOrb.AnchorPoint`/`Position`/`Size`
directly, so the aura starts in exactly the same rectangle as the orb
regardless of how it's really anchored, and stays centered on it when
scaled up rather than risking a lopsided drift to one side.

## 25. Crit Streak Combo -- a luck-based escalating callout

A "COMBO x3!" / "MEGA COMBO x5!" / ... up to "LEGENDARY x20!" callout
for landing several criticals in a row, escalating in color, text
size and burst intensity at each tier. Resets silently on the first
non-crit -- no punishment beat, just no reward beat, matching how
Momentum already just quietly zeroes out rather than announcing a
combo ending.

**Deliberately not a third copy of an existing streak system.** This
codebase already has two: Momentum (`rebirthshop_momentum`) is a
CADENCE streak (how fast you're clicking) that feeds a real gameplay
bonus, and `collectStreak` in `CursorCollection.client.luau` is also
cadence-based, purely for audio pitch, reset by a pause. This one is a
LUCK streak -- consecutive criticals, independent of timing, reset
only by a non-crit landing -- and it's purely cosmetic. Crits already
pay out correctly server-side (`EssenceMultiplier`/
`CriticalsController`) whether or not this script exists.

**One small, minimal addition to `CursorCollection.client.luau`** was
needed to make this possible: a new `CritLanded` BindableEvent
(created/owned by the new script, same ownership convention already
used by `EssenceDiscovered`/`NewDiscovery.client.luau`), fired with
the exact same `IsCrit` flag that file already reads for its own
per-orb effects a few lines above -- one new local variable, one new
`:Fire()` call, nothing existing reordered or changed.

## 26. Three fixes in the Settings panel (Music/SFX toggles)

Continued the file-by-file audit into `SettingsUIManagement.client.
luau`, which had gone unchecked all pass. Found three real issues in
its `applyButtonFeel` helper and click handler:

1. **Unguarded nil UIScale.** `local UIScale = parent:FindFirstChild
   ("UIScale")` had no fallback, and every hover/press handler
   immediately does `TweenService:Create(UIScale, ...)` -- a nil
   target there throws. If either toggle's parent didn't already have
   a UIScale pre-built in Studio, hovering or pressing it would error
   on every interaction (the actual on/off logic lives in a separate
   `MouseButton1Click` connection, so this wouldn't have silently
   broken the setting itself -- just spammed errors and killed the
   hover feel). Fixed with a find-or-create fallback.
2. **`hoverScale` was accepted as a parameter and then completely
   ignored** -- every call already passes `1.3`, but the hover tween
   hardcoded `1.05` instead. Restored so the parameter does what its
   name says. Also removed a `baseSize`/`scaled()` helper that was
   defined but never called anywhere -- leftover from an earlier
   Size-based tweening approach, replaced at some point by the
   UIScale-based one visible now, never cleaned up.
3. **The actual toggle logic** (`MouseButton1Click`) read `button.
   Parent:FindFirstChild("TextLabel").Text` with no nil-check, twice,
   once per branch. Unlike the hover-feel issue above, a missing label
   HERE would have broken the setting's actual on/off behavior on
   every click, not just its animation. Deduplicated into one guarded
   lookup shared by both branches.

## 27. The Index popup's tooltip was completely broken -- plus the same UIScale bug in 3 more files

Continuing the sweep through `src/StarterGui`'s popup scripts turned
up the single most certain bug of this whole pass -- not a "might
happen if X is missing" risk, a guaranteed failure on every use.

**`IndexUIManagement.client.luau`'s hover tooltip used `.value`
(lowercase) to read a `BoolValue`'s data.** Roblox's `BoolValue` (like
every `*Value` instance) stores its data in `.Value` -- capital V,
case-sensitive, no fallback. `PlayerDataHandler.server.luau` confirms
exactly this: `Instance.new("BoolValue"); V.Value = discovered`.
Reading `.value` on that instance throws immediately -- and since this
line ran *before* `popup.Visible = true` in the same synchronous
`MouseEnter` handler, the error aborted the whole handler right there.
Net effect: hovering ANY essence slot in the Index/compendium popup
never showed the tooltip at all, for any player, ever. This is
literally the popup's entire purpose. Fixed both occurrences
(`.value` -> `.Value`).

**Same popup, second fix:** the slot-validity check was `if slot.Name
~= "Frame" then` -- a blocklist excluding one specific name, rather
than checking against what the code actually needs (`EssenceDatas`
only defines `"Earth Essence"`/`"Shadow Essence"`). Any other non-
"Frame" child in that grid would have hit `Data[slot.Name].Rarity` on
a nil table and errored. Changed to check `Data[slot.Name]` directly --
the real requirement, and self-documenting about what "a valid slot"
means here. Also removed a leftover debug `print`.

**Third, unrelated finding in the same file, also present in
`InventoryUIManagement.client.luau` and `ZonesUIManagement.client.
luau`:** all three share (copy-pasted, it looks like) the exact same
`applyButtonFeel` helper `SettingsUIManagement.client.luau` already
had fixed in section 26 -- an unguarded nil `UIScale` that throws on
every hover/press if a toggle's parent doesn't already have one, and a
`hoverScale` parameter silently ignored in favor of a hardcoded
`1.05`. Applied the identical fix to all three (find-or-create
UIScale, use the actual `hoverScale` argument). `ShopUITweens.client.
luau` was already checked earlier (section 23) and uses a different,
unaffected technique (tweens `Size` directly, no `UIScale` involved).

## 28. Friend Bonus -- a free, zero-setup essence bonus for playing with real friends

A small, permanent essence bonus for having real Roblox friends present in
the same server -- the other proven social/viral mechanic in this genre,
alongside Group Reward (section 17), and deliberately simpler to turn on:
Group Reward needs a real Group ID before it does anything, but
`Player:IsFriendsWith` needs no setup at all, so this is live for every
player from the moment it's synced in.

**How it works.** `FriendBonusService.server.luau` recomputes, on every
`PlayerAdded`/`PlayerRemoving`, how many of the OTHER players currently in
the server are real friends of each player, and mirrors the count onto a
`FriendsInServer` attribute. `EssenceMultiplier.luau` reads it exactly like
every other multiplicative bonus in that file (+5% per friend present,
capped at 4 friends / +20% -- see `FriendBonusConfig.luau`, the single
source of truth both the multiplier and the client display read from so
they can't drift apart). A small badge (`FriendBonusIndicator.client.
luau`) appears top-right whenever the count is above zero, showing the
live "+N% Essence / N Friends Online" -- and stays completely hidden
otherwise, since there's nothing to explain in the common case of playing
solo or with strangers.

**Why this can't be a "compute once at join" cache like Group Reward.**
Group membership only ever depends on the player being checked. Friend
presence depends on who ELSE is in the server -- one player joining or
leaving changes the correct answer for everyone else already there. So
every join/leave recomputes the whole server's counts (O(players²)
`IsFriendsWith` calls per event), which is trivial at this game's server
sizes and only ever runs on the join/leave event itself, never a poll or
a per-frame loop.

**A real race I found and fixed before committing this.** `IsFriendsWith`
yields (it's a genuine network call), so two joins/leaves within the same
second or two produce two overlapping recompute passes -- and without a
guard, the slower one can finish last and overwrite a newer, more complete
recompute with stale data. Fixed with the same token-supersession pattern
`Juice.CountUp` already uses for concurrent count-up animations: a pass
that's been superseded by a newer one stops writing instead of racing it.
Self-healing either way (the next join/leave corrects it), but there was
no reason to ship the race when the fix already existed as a codebase
idiom.

Neither `FriendsInServer` nor anything about this system is ever written
by the client -- `IsFriendsWith` is a server-only check against Roblox's
own friends graph, so unlike some of this session's other additions,
there's no new trust boundary here at all.

## 29. Closed the most severe exploit found this session: forgeable currency and a free permanent 3x

`OrbClickManager.server.luau`'s `collected` RemoteEvent handler --
the ONE place every single essence reward in the game gets credited
-- trusted two client-supplied values it had no business trusting
outright: `quantity` (an orb's base essence value) and `gold`
(whether it counts as a golden-storm orb, worth a flat 3x).

**`quantity` had no bound at all.** Orbs are purely client-side visual
objects: `OrbClicker.client.luau` computes and sets `EssenceValue` on
each one locally, `CursorCollection.client.luau` reads it back off the
orb and sends it straight to the server as `quantity`. The server has
no independent record of what any given collection "should" be worth
-- so a direct `FireServer("Earth Essence", 999999999, false, false)`
call (no exploit sophistication required; this is closer to the
*first* thing anyone probing a game's remotes tries) would have
credited exactly that, permanently, straight into saved `PlayerData`
and the "Top Essence" global leaderboard. Worse than the badge exploit
in section 19: that one handed out cosmetic-ish achievements, this one
is the entire economy this session spent real effort balancing (see
sections 19-20 from earlier in this file). Fixed with
`MAX_QUANTITY_PER_COLLECTION` (5000) -- a generous sanity ceiling, not
a precise recompute of the legitimate formula. Legitimate play (even a
maxed `root_awakening` at 32x base, fused through a maxed Gravity
Well's +20% bonus) stays far under it; it exists purely to block the
"claim an arbitrary huge number" case. Non-numeric, NaN, and
non-positive quantities are rejected the same way the pre-existing
`orbName` check already rejected malformed input.

**`gold` went straight into a flat, unconditional 3x with no check at
all** -- and this one isn't even a case of the codebase never having
thought about it: `StormController.luau`'s own header comment
documents the intended fix verbatim ("Applying the golden-storm reward
multiplier to collected essence... by checking
`player:GetAttribute('StormIsGolden')` at the moment of collection")
-- it just was never actually wired up where collection is credited.
Any client could `FireServer` with `gold=true` on every single
collection for a permanent, unconditional 3x with no storm ever
active. Fixed by re-deriving it server-side (`gold and
plr:GetAttribute("StormIsGolden") == true`) instead of trusting the
parameter -- `StormIsGolden` is already a real, server-authoritative
attribute (`StormController:_mirrorAttributes` sets it, only the
server ever calls that), so legitimate play is completely unaffected.

**Deliberately left alone:** the `crit` boolean has the same shape as
`gold` (a client-supplied flag) but isn't a bug -- `CriticalsController.
luau`'s own "DESIGN NOTE ON TRUST" explains why: the flag only decides
*whether* a bonus applies, and the bonus *amount* is always derived
from the player's own `CritMultiplierBonus` attribute total, so a
forged `crit=true` can never grant more than upgrades already bought
justify. `gold` had no equivalent derivation (a flat 3x isn't tied to
any attribute at all), which is exactly why it -- unlike crit -- needed
a fix.

## 30. Hardened UpdateData against a crash (not an exploit -- checked carefully)

While auditing every remaining `OnServerEvent`/`OnServerInvoke` handler
after section 29's fix, `UpdateData.server.luau` -- the generic
"write one of my own preference/flag fields" endpoint -- was worth a
close look: a hand-rolled path-based mutator is exactly the shape a
real exploit usually hides in.

It doesn't. `ALLOWED_ROOTS` gates `path[1]` to exactly six fields
(`Settings`, `SeenTutorial`, `SeenFirstCrit`, `SeenFavoritePrompt`,
`SeenWhatsNewVersion`, `HollowedMilestones`), the traversal only ever
descends from that root, and every one of those six is either a plain
scalar or one flat table of booleans -- there's no path that reaches
`Essences`, `Rebirths`, or anything else that actually matters. Traced
this all the way through before concluding it's genuinely safe, the
same way section 29 was traced through before concluding it wasn't.

What it DID have: a client sending a path with more segments than the
real data shape supports (e.g. a third segment under `SeenTutorial`,
which is just `true`/`false`, not a table) would try to index that
boolean and throw "attempt to index a boolean value" -- crashing that
one call with an error in the output rather than the same clean reject
every other malformed-input case in this codebase gets. Same for an
arithmetic operator (`+`/`-`/`*`/`/`) against a non-numeric `Value`.
Neither was reachable for any gain (the field you'd land on is your
own settings toggle or "have I seen this popup" flag either way) --
just a rough edge, not a hole. Added a `type(currentFolder) ~= "table"`
guard before descending and a numeric check before the arithmetic
operators, both rejecting with a `warn` instead of erroring. Also
removed a leftover `print("Reached target data:", ...)` that fired on
every single write.

## 31. Two more ProductPurchaseHandler bugs -- a delayed grant and a stat that could inflate on retry

A third pass over `ProductPurchaseHandler.server.luau` (after section
18's nil guard and section 23's hang-risk fix -- this file has now had
more individual bugs than any other single file this session) turned
up two more, both in the RobuxSpent bookkeeping rather than the
purchase-granting logic itself.

**`PromptGamePassPurchaseFinished` ran an unguarded
`GetProductInfoAsync`** -- a real network call to Roblox, with the
documented failure modes any network call has -- BEFORE looking up and
calling the actual grant handler. A transient failure there aborted
the whole connected function, so the player's gamepass simply didn't
get applied for that purchase. Not a permanent loss -- Roblox already
recorded the sale on its own side regardless of what this script does,
and `grantOwnedGamePassesOnJoin` re-checks real ownership on every
join -- but `PromptGamePassPurchaseFinished` itself fires exactly once
with no Roblox-level retry (unlike `ProcessReceipt`, which Roblox
explicitly keeps retrying), so the practical effect was: a player who
just paid would see nothing until they rejoined. Fixed by wrapping
just the RobuxSpent bookkeeping in its own `pcall`, separate from the
handler lookup/call, so a failure there can never skip the actual
grant.

**`ProcessReceipt` credited RobuxSpent before confirming the purchase
would actually be granted.** An unregistered product id, or a handler
that legitimately returns `false` to ask Roblox for a retry (Essence
Rain does this on purpose when a storm can't start yet), both return
`NotProcessedYet` -- which means Roblox calls `ProcessReceipt` again
later for the exact same purchase. Since the RobuxSpent line ran
before either of those checks, every one of those retries re-credited
it again, with no cap. Moved the credit to right alongside the
`purchaseHistoryStore` write that already exists specifically to make
a receipt "count" exactly once -- now RobuxSpent shares that same
one-time guarantee instead of running on every attempt.

## 32. A narrow but real data-loss race between autosave and server shutdown

`PlayerDataHandler.server.luau` -- the central load/save system, gone
through carefully since a bug here risks actual player progress -- is
mostly excellent: `applySavedData`'s recursive merge correctly handles
schema changes in both directions (a new template field a player's old
save doesn't have keeps its fresh default; a field removed from the
template but present in an old save is just harmlessly ignored/carried
along), and every mutation path reads well. One real race turned up in
how it shuts down.

`savePlayerData` uses a `saveLocks[userId]` flag so two saves for the
same player can never run concurrently and corrupt each other's
write -- if one's already in flight, a second call just no-ops
immediately. That's exactly right for the common case: autosave firing
again while a previous autosave is still finishing is fine to skip,
since another one runs in 2 minutes regardless.

It's NOT fine in `game:BindToClose`. The shutdown handler calls
`savePlayerData(player, true)` for every player and decrements a
`remaining` counter right after, so its own wait-loop knows when it's
safe to let the server actually close. But if an autosave happened to
be mid-flight for some player at the exact moment the server started
shutting down, `savePlayerData` would hit the lock and return
immediately -- `remaining` still decrements right away, `BindToClose`
concludes everyone's saved and can return almost instantly, while the
REAL in-flight save (the one actually holding the lock) keeps running
as an independent, un-awaited coroutine that the process terminating
shortly after could kill mid-write. The window is narrow and the loss
when it happens is usually small (whatever changed in the last moment
before that autosave's own snapshot), but it's real, it's silent, and
losing progress is exactly the kind of thing that makes a player not
come back.

Fixed without touching the lock itself or the common autosave path:
each `BindToClose` task now waits (capped at 20s) for `saveLocks
[userId]` to actually clear before counting that player done, so a
pre-existing in-flight save gets the time it needs instead of being
silently treated as already finished.

## 33. Streak Freeze -- missing one day no longer has to erase the whole streak

`ProgressionConfig.luau` already documented, in its own words, that the
daily streak's reset-on-miss is "kept deliberately gentle: nothing is
ever permanently lost, there's no way to pay to restore a streak, and
the UI never uses countdown pressure about losing it." That's a good
principle, and worth actually respecting rather than quietly working
around it -- so this doesn't touch any of it. It adds a second gentle
thing alongside it.

**Streak Freeze**: earned for free every 7 days of an active streak
(the same cadence as the existing day-7 "standout" reward), banked up
to 3. Missing exactly one day now consumes a freeze and continues the
streak instead of resetting it, if one is banked -- missing two or
more days still resets it fully, same as always. Never purchasable
(no monetization angle on loss aversion, which is exactly the kind of
thing the existing "gentle" design was already avoiding), and never
shown as a warning or a countdown -- the daily panel's status line
just quietly shows `🛡️ x2` once you've earned any, and a claim that
uses one says so in its reward toast ("🛡️ Streak Saved -- Day 6
Streak!") rather than the game ever telling you a streak is at risk
beforehand.

Touches three files, each holding exactly the piece that belongs
there: `ProgressionConfig.luau` has the two tunables (frequency, cap)
alongside the existing streak config; `ProgressionService.server.luau`
is the only place that reads or writes `StreakFreezes` (consume/earn
logic in the claim handler, included in the sync payload, and folded
into the `PendingStreak` preview so the panel never shows a number the
claim itself wouldn't actually produce); `ProgressionHud.client.luau`
only adds the one status-line suffix, no new panel or button.

## 34. The collection floating text could show a number that didn't match what you actually got

Found while reading `CursorCollection.client.luau` end to end (it
hadn't had a full pass since the exploit fixes in sections 29/31 --
worth checking the CLIENT half of that same boundary too). The "+N"
text that floats up off a collected orb calls
`EssenceMultiplier.CalculateMultiplier` client-side to compute what to
show -- purely for that animation, since the real grant only ever
happens through `OrbClickManager.server.luau`'s own, separate call to
the same function.

The problem: `CalculateMultiplier` rolls `double_crit` internally
(`math.random()`, inside `RollCritMultiplier`) whenever `crit` is
true. Calling it client-side for the preview and server-side for the
real grant means TWO independent rolls of the same coin for what's
supposed to be one crit -- `EssenceMultiplier.luau`'s own comment
already warned about calling this function twice for one collection
event, just for the case of calling it twice within one script. This
was the same mistake, split across the client/server boundary instead.
For any player who owns `double_crit` and lands a crit, the floating
number and the leaderstat's actual increase could disagree -- exactly
the kind of small inconsistency that undermines the single most
important feedback signal in an idle game.

Fixed with an optional 4th parameter, `skipDoubleCritRoll`, defaulting
to unset so the one real grant path (`OrbClickManager.server.luau`)
is completely unaffected. When a caller passes `true`, the crit
contribution is computed deterministically with `double_crit` off
instead of rolled -- an honest floor (occasionally shows a little
LESS than double-crit ends up granting, never more), and, since
nothing reads this return value as an actual credit, not something a
forged client could exploit for a real payout either way.
`CursorCollection.client.luau`'s one call site now passes it.

## What to check when you open Studio

1. **Press play and confirm essence actually goes up.** This is the whole
   ballgame. Click the orb, hover a drop, watch the counter. If it moves,
   the core bug is fixed.
2. **Play through the tutorial's first step as a genuinely new player
   would** — don't just click Next. Confirm the step actually waits for a
   real collection and advances itself (with a short celebration) once
   one lands, and that the 14s/34s hints and the 58s fallback Next button
   show up if you deliberately do nothing.
3. **Check the new buttons** (🌑 Sanctum / 🔮 Prestige Shop / 🏆 Ranks /
   🏅 Goals, then 🎁 Daily / 📜 Quests / 🎟️ Codes lower down, plus 👥 Group
   if you've configured a Group ID) on the right edge don't overlap your
   existing UI. **Section 17 below has a real collision this pass fixed**
   between the Daily/Quests/Codes stack and the Sanctum/Prestige Shop
   buttons -- worth confirming the fix actually looks right on your real
   screen size, since this was corrected from source math, not a visual
   check. Positions live in the `LAYOUT` table at the top of
   `ProgressionHud.client.luau`, `SanctumPanel.client.luau`,
   `RebirthShopPanel.client.luau`, `LeaderboardPanel.client.luau`,
   `AchievementsPanel.client.luau` and `GroupRewardPrompt.client.luau` —
   one line each, no hunting.
4. **Try a code** (`LAUNCH`) to confirm the redeem flow works end to end.
5. **Watch the Output window** for red errors on join.
6. **Daily panel auto-opens** on a first join once the tutorial is done.
   If you'd rather it didn't, delete the "FIRST-SESSION NUDGE" block at
   the bottom of `ProgressionHud.client.luau`.
7. **Leaderboards need DataStore access to show anything.** In Studio,
   turn on Game Settings → Security → "Enable Studio Access to API
   Services", or test in a real server -- without it, the panel will
   correctly show "No rankings yet" forever rather than erroring, but you
   won't see real data until that's on (or the game is published/live).
8. **"What's New" popup won't appear on a fresh account** in Studio
   testing by design (see section 16 -- first-ever sessions skip it). To
   see it: play through the tutorial once so `SeenTutorial` saves as
   `true`, stop the server, then press play again with the same test
   account -- the popup should appear a few seconds after join. To re-test
   repeatedly after that, just bump `WhatsNewConfig.CurrentVersion` by 1
   each time rather than trying to reset the save.
9. **Group Reward is invisible until you configure it, on purpose.** Set
   `GroupRewardConfig.GroupId` to your real group id to turn it on (see
   section 17), then confirm the 👥 button opens the right group page
   and disappears once your test account actually joins that group and
   rejoins the game.
10. **Confirm the loading screen still plays its glitch sounds AND still
    reaches the game** (see section 22, both fixes). Both should be
    silent/invisible if everything's already set up correctly in
    Studio -- press play once and confirm you hear the glitch sounds
    during loading, then confirm the loading screen actually fades out
    and drops you into the game, the music starts (`SoundController`),
    and (if you've played through the tutorial before on that account)
    the Hollowed One ambient effects are running. If loading ever
    hangs and never fades out, check that `ReplicatedStorage.Remotes.
    LoadingDone` actually exists -- this fix creates it automatically
    now, so that specific failure shouldn't be possible anymore, but
    it's worth knowing what to look for if loading ever seems stuck.
11. **Prestige Aura (section 24) needs an account with real rebirths**
    to see anything -- a fresh save shows nothing at all, correctly.
    Fastest way to check it: give a test account `Rebirths` levels 1,
    5, 10, 25 and 50 via the command bar one at a time
    (`game.Players.YourName:SetAttribute("Rebirths", 10)`) and confirm
    the glow around the great orb changes at each one, growing more
    elaborate, plus a burst + float-text + punch fires each time
    (**not** on the very first `SetAttribute` call after joining --
    that one's treated as "already had it," same as everything else
    in this codebase that avoids celebrating already-reached progress
    on join). Also confirm the aura sits centered on the orb rather
    than offset to one side -- if it looks off-center, `LargeOrb`'s
    real `AnchorPoint` turned out to need more than a copy of its
    Position/Size/AnchorPoint (see section 24's note on why this was
    derived rather than hardcoded).
12. **Crit Streak Combo (section 25)** needs a real crit-heavy run to
    see escalate -- land 3+ criticals in a row (a high `CritChance`
    upgrade or Shadow Sanctum's Dark Fortune makes this fast to test)
    and confirm the "COMBO x3!" callout appears at the orb, growing
    more dramatic at 5/8/12/20, and disappears silently (no callout at
    all) the moment a non-crit breaks the streak.
13. **Open the Index/compendium popup and hover an essence slot**
    (section 27) -- this should have been completely broken before
    this pass (no tooltip ever appearing, silently). Confirm you now
    see "Rarity: ... / Discovered: true/false" follow your cursor, and
    that hovering/pressing the popup's buttons scales smoothly instead
    of throwing (same for the Inventory and Zones popups).
14. **Friend Bonus (section 28) needs a second real Roblox account that's
    actually friends with your test account** -- Studio's multi-client
    test (or two Roblox windows logged into two real, friended accounts)
    is the only way to see it fire; a solo Studio playtest will correctly
    show nothing. Once both are in the same server, confirm the 👥 badge
    pops in top-right on BOTH accounts showing "+5% Essence / 1 Friend
    Online", and that it updates live (no rejoin needed) if one of them
    leaves.
15. **Section 29's fix shouldn't change anything you can see or feel.**
    Play normally -- click, collect, get a golden storm going (manual
    summon or wait one out) -- and confirm essence still climbs exactly
    as before. This fix only rejects requests a real client would never
    send in the first place; if a legitimate collection ever gets
    rejected (an `[OrbClickManager] Rejected malformed/out-of-range
    collection` warning in the Output window during normal play, not
    from you poking a remote directly), that's a sign
    `MAX_QUANTITY_PER_COLLECTION` needs raising -- it's a single number
    at the top of `OrbClickManager.server.luau`.
16. **Streak Freeze (section 33) needs a simulated missed day** to see
    fire -- waiting a real day in Studio obviously isn't practical. With
    a test account: claim once normally, then in the command bar run
    `require(game.Players.YourName.PlayerData).Progression.LastClaimDay -= 2`
    to fake having missed yesterday, then claim again. With 0 freezes
    banked (the default for a fresh save) this should reset to Day 1 as
    normal -- confirm the OLD behavior still works. To see a freeze
    actually save a streak, first get one banked (either claim 7 days in
    a row the same way, decrementing `LastClaimDay` by 1 between each
    claim instead of 2, or just run `...Progression.StreakFreezes = 1`
    directly), then repeat the `-= 2` simulated-miss step -- the streak
    should continue instead of resetting, the toast should read "🛡️
    Streak Saved", and the daily panel's status line should show one
    fewer freeze banked.

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
