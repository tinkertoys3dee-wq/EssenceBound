# What changed, and what to check in Studio

Changes on `claude/retention-and-captivation`. Everything below is
either a bug fix to existing code or a self-contained new file — no
existing gameplay system was restructured.

---

## 0. UPDATE: all three previously-dead Game Passes are now wired up

This section used to be a "READ THIS FIRST" warning that three Game
Passes took real Robux and did nothing at all -- explicitly left
unfixed at the time since guessing what a paid feature should do isn'
a call to make unilaterally. All three are now implemented against
their REAL store descriptions (see sections 39 and 40 for the full
writeups):

| Game Pass | Id | Store description | What it does now |
|---|---|---|---|
| Dedicated Essence | `1907077899` | (name only) | Sharpens whichever Zone you're standing in toward its specialty essence (section 39) |
| Lucky Finder | `1907239833` | "Increases the base chance of finding rarer essences by 50%." | ×1.5 to every non-common essence weight (section 40) |
| Ultra Luck | `1906063939` | "Stacks with regular luck to give a massive boost (x3 luck)." | ×2 to every non-common weight alone, ×3 total combined with Lucky Finder (section 40) |

**An earlier version of this pass guessed crit chance for Lucky
Finder/Ultra Luck before their real store text was available --
wrong, replaced entirely once it was.** "Rarer essences" now means both
Shadow (Rare) and Solar (Mythic), while Earth remains Common -- both
passes multiply every non-common weight inside
`ZonesConfig.GetEssenceWeights`, the exact same function Dedicated
Essence and Zones already share, so all three "Luck"-flavored passes
and the odds a player actually sees all come from one place.

For comparison, the other four Game Passes in this file already did
something real before any of this: VIP Rank (`1909291891`) gives a
gold name/icon outline (`UIInitializerHooks.client.luau`), 2x Essence
Multiplier (`1907605899`) is read in `EssenceMultiplier.
CalculateMultiplier`, Auto Absorption (`1907677938`) is read in
`CursorCollection.client.luau`'s collection loop, and Material
Alchemist (`1907863864`) raises the offline-earnings base rate from 10%
to 50% in
`IdleService.server.luau`.

---

## Zones no longer require a manual Studio setup step

Section 39 still prefers the authored **`ZonesButton`** under
**`MainGui.Right.Holder`**, accepting either a real GuiButton or a Frame
that wraps one. If that instance is missing, renamed, or lost during
syncback, `ZonePanel.client.luau` now creates a styled fallback in the
same navigation slot. The picker, travel animation, and zone ambience
therefore remain reachable without any manual repair in Studio.

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
corner. Its first flash/callout pass fixed the silence; section 47 now
supersedes that small treatment with a complete tri-essence storm-eye
arrival, persistent weather, lightning, energy rain, real Earth/Shadow/Solar
orb previews, comet-tailed collectibles and a distinct exit. Golden storms
receive their own stronger palette and sound. This remains purely
cosmetic; duration, spawn rate, collection validation, payouts and the
server's golden roll are untouched.

Earth rewards scale with rebirth count, while fixed mythic Solar bonuses
preserve their endgame value. Nothing here costs Robux or pressures a
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
all essence types combined) and `RebirthsLeaderboard`. Deliberately
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

## 17. Fixed a real button collision, added a Group Reward

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
permanent essence bonus for players who've joined the game's Roblox
group -- unlike a gamepass, group membership actively
helps the game itself (shouts, wall posts reach every member). Checked
on join server-side (`Player:IsInGroup`, cached to a `GroupMember`
attribute so hot reward paths never make a live API call) and folded into
the same server-owned bonus stack used by the rest of the game. It is
configured for **Mundane Studios** (group `15575113`) with three permanent
member benefits: **+35% essence**, **+5% critical chance**, and **+15%
offline earnings**. The essence bonus is read by `EssenceMultiplier`, the
crit bonus is added and capped inside `CriticalsController`, and the extra
offline bonus is applied by `IdleService`; the client only displays the
same values from `GroupRewardConfig` and cannot grant any of them.

Non-members see a delayed, responsive community panel plus a persistent
FREE reminder button. The panel now has a layered EssenceBound-style
frame, animated ambient glows, a community crest, three dedicated benefit
cards, clearer verification states, outside-click/Escape closing, and a
short success confirmation. It opens the community page through
`GuiService:OpenBrowserWindowAsync`, and its "I've joined" action asks the
server for a rate-limited authoritative recheck so every benefit can
activate without requiring a rejoin.

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

## 35. Fortune Wheel -- a genuinely new mechanic, not another variation on what's here

Everything added this session before this point extended an existing
loop (a bonus multiplier, a streak safety net, a fix). This is the
first actually NEW gameplay mechanic since the Prestige Shop/Sanctum:
a spinning wheel with 8 weighted rewards, one free spin on a rolling
24h cooldown, plus extra spins earned as tickets from actually playing
(one ticket per 60 orbs collected, banked up to 5).

**Why this and not another daily-login variant.** The daily streak's
appeal is commitment -- you know the reward, the pull is not breaking
the chain. Quests' appeal is a session having a shape. The wheel's
appeal is suspense -- you don't know what you're about to get until it
stops spinning, which is a different psychological hook (variable-
ratio reinforcement, the same mechanism behind loot boxes and slot
machines, used here without any of the parts that make those
predatory: every segment is a genuine, positive reward -- see section
0 and the Daily Rewards design note for why this game deliberately
never has a "you got nothing" outcome -- nothing here costs Robux, and
the whole reward table is visible on the wheel itself, not hidden
behind a paywall or a mystery box). Tying extra spins to actual
collecting (not just logging in) also reinforces the CORE loop in a
way the daily streak and quests don't -- click and collect, and the
wheel is one more thing steadily filling up in the background.

**How the wheel spins without a pie-chart primitive.** Roblox UI has
no native pie-slice shape. `WheelPanel.client.luau` arranges all 8
reward badges around a circular "ring" Frame at fixed angles (basic
trig) and spins the whole ring by tweening its `Rotation` property --
rotating a GuiObject carries every child positioned inside it around
as one rigid unit, so the badges visually swing like a real wheel with
no image assets needed. A separate pointer stays fixed outside the
ring. The math always spins FORWARD from wherever the ring currently
is (never snaps backward) and adds several extra full turns before
landing exactly on the segment the server has already decided.

**The presentation is now a full astral arcade cabinet, matching the
quality bar set by the Prophecy Crystal.** The larger, deliberately
padded modal has a layered wheel face, radial dividers, 24 pulsing
cabinet bulbs, counter-rotating energy rings, orbiting runes, an
illuminated hub and jewel reward pedestals that remain upright while
their positions spin. A fixed pointer visibly ticks across candidates
as the wheel accelerates and decelerates, while the prize ledger keeps
all eight rewards and their exact percentage chances readable beside
the action. The landing replaces that ledger with a dedicated result
chamber showing the player's actual rebirth-scaled grant, not merely
the segment's base value. Common, Uncommon, Rare, Epic and Jackpot
presentation tiers progressively add stronger color, rings, particles,
flash and shake; the 1% Jackpot receives the complete celebration.
These tiers are visual escalation only and do not alter a single weight
or reward.

The bottom-right DAILY shortcut now reads its initial state through a
`GetWheelState` RemoteFunction as well as continuing to receive live
`WheelSync` pushes. That closes the startup race where the old client
could miss the one delayed event and remain visually stuck loading,
while the server's own clock remains authoritative for the free-spin
countdown.

**Server-authoritative, same as every purchase flow in this
codebase.** `WheelService.server.luau` rolls the segment
(`WheelConfig.RollSegmentIndex`, weighted, server-side only) and grants
the reward BEFORE the client ever finds out what it won -- the client
only ever asks to spin and is told the result afterward, the same
"only ask, never decide" contract every other remote in this game
follows. Essence rewards scale with rebirths through the same
`ProgressionConfig.ScaleReward` every other reward system already
uses, so the wheel stays meaningful for veteran players without a
second scaling formula to keep in sync.

**A design refinement caught in self-review, not left as a rough
edge:** tickets were originally reset to 0 progress even when a
collection happened while already holding the max 5 banked (since the
6th would never be granted anyway) -- meaning active play while capped
just wasted progress for nothing. Changed so ticket progress PAUSES
at the cap instead of resetting, resuming exactly where it left off
the moment a spin frees up room, so no play ever earns literally
nothing.

**Also fixed alongside this (small, not severe):** `ProgressionService.
server.luau`'s own quest-progress listener on the `Collection` remote
counted an event as "one orb collected" without checking `orbName` at
all -- unlike `OrbClickManager`'s real reward path, which already
rejects a garbage orbName outright (see section 29). A client could
have farmed quest progress by firing `Collection` directly with an
invalid orbName that never reaches a real reward. Bounded (quests are
still claimable only once per slot per day regardless), but real, and
exactly the same bar the wheel's own new ticket-listener needed from
the start -- so both got the same fix.

## 36. Biggest Gain -- a session personal best, entirely client-side

A small addition in the same spirit as the Fortune Wheel but much
smaller in scope: `BiggestGainCelebration.client.luau` celebrates the
single biggest Earth Essence gain observed since you joined -- a lucky
crit, a golden storm hit, a Wheel jackpot, a big quest reward, any
source -- whenever a new one beats the last by a real margin (20%+,
so it isn't a stream of toasts for trivial increments). Distinct from
`UIManagement.client.luau`'s existing milestone celebrations, which
fire when the CUMULATIVE total crosses a round threshold (1K, 10K,
...) -- this is about one single collection event being the biggest
one yet, regardless of the running total.

**Deliberately session-only, and deliberately not a server feature.**
A genuine lifetime record would need server-side tracking to be
trustworthy for anything beyond your own screen -- this doesn't claim
to be that. It's a pure, honest readout of deltas this client already
legitimately observes on its own leaderstat, reset every time you
rejoin. That scoping is what let this ship as a single, fully
self-contained client file with no new remotes, no new PlayerData
field, and no trust question to reason through at all.

Setup waits ~7 seconds after join on purpose: `IdleService.server.
luau` grants offline earnings through the exact same leaderstat about
5 seconds after join, and a big offline lump sum would otherwise fire
a "New Best" banner right on top of `RecieveOfflineEarning.client.
luau`'s own dedicated Welcome Back popup, competing for the same
number at the worst possible moment. Waiting past that window means
the offline grant is already baked into the starting baseline instead
of being treated as a trackable gain.

**Caught in self-review:** the reveal animation played a Back-Out
tween on the banner's UIScale (0.7 -> 1, which already overshoots
past 1 before settling -- that's where the "pop" comes from) AND
called `Juice.Punch` on the same UIScale right after. `Punch` reads
`Scale` synchronously to decide its own resting point -- since tweens
animate over subsequent frames rather than instantly, it would have
read the pre-tween 0.7, wrongly captured that as "resting," and
fought the reveal tween outright, leaving the banner stuck visibly
smaller than intended. Removed the redundant Punch call; the Back-Out
easing already provides the punch on its own.

## 37. The tutorial's Upgrades step now makes you actually buy something

Same underlying problem as the old orb-collect step (section 22, much
earlier): showing a menu and narrating what it does is not the same as
a player actually doing the thing, and "shown" doesn't stick nearly as
well as "did." The Upgrades step used to just point at the menu, say
"Spend your essence in the UPGRADES menu to level up your power!", and
let you click Next immediately -- completable without ever opening the
menu, let alone buying anything. Worse, a brand-new player reaching
this step has collected at most one or two orbs -- a few essence,
nowhere near `root_awakening`'s 15-essence cost -- so even a player who
DID open the menu on their own usually couldn't afford anything yet.

Two pieces, same trust boundary as every other server-authoritative
system in this codebase:

- **`TutorialStarterGiftService.server.luau` (new).** The instant this
  tutorial step begins, the client fires `RequestTutorialStarterGift`
  and the server grants a flat +50 Earth Essence -- comfortably enough
  for `root_awakening` with room to explore a second cheap option too.
  Server-validated and one-time per player via a new
  `SeenTutorialStarterGift` flag in `DefaultPlayerData.luau` (mirroring
  `SeenFirstCrit`/`SeenFavoritePrompt`'s existing pattern): the client
  can only ever ask, the flag is what actually makes "one time" mean
  once, and a forged repeat request just hits the same check and gets
  nothing.
- **`Tutorial.client.luau`'s new `startFirstUpgradeWatch`.** The step
  no longer advances on a timer or a bare Next click -- it watches the
  Earth Essence leaderstat for a genuine DECREASE, the one unambiguous
  signature of a real purchase, using the same delta-comparison pattern
  `BiggestGainCelebration.client.luau` already uses in the opposite
  direction (compare each change against the immediately-preceding
  value, not a fixed baseline, so it's correct regardless of how many
  increases happen first from ordinary orb-clicking). Watching for
  "any decrease" rather than trying to detect which specific upgrade
  keeps this robust to whichever one the player actually picks. Same
  shape as the orb-collect step: escalating hint text (10s, then 24s
  total) and a fallback Next button after that, so nobody is ever
  hard-walled if a click genuinely isn't landing.

**Self-corrected before committing:** the first draft of the
decrease-detection logic used a more convoluted "baseline only ever
ratchets upward" scheme. On review that was harder to convince myself
was airtight than necessary for what it's protecting against, so it
was replaced with the simpler delta-comparison above -- fewer moving
parts to be wrong about, and it's the same pattern already proven
elsewhere in this codebase.

## 38. New Adventurer's Luck -- extra-frequent crits for a brand-new player's first 24 hours

A totally fresh player sees exactly one crit before this (the
guaranteed first-click one, `SeenFirstCrit`) and then nothing else
until click ~16, since base `CritChance` from the upgrade tree starts
at 0. Crits are this game's single biggest "wow" moment -- bigger
tint/glow/pop, a badge, and the Crit Streak Combo callout for
back-to-back ones -- so a 15-click dead zone right after the best
first impression the game has is exactly the wrong place for one.

`NewPlayerLuckConfig.luau` grants a flat +15% crit chance and shortens
the guaranteed-crit-streak wait by 6 clicks, both still bounded by
`CriticalsController`'s own existing caps (`MAX_CRIT_CHANCE`,
`MIN_GUARANTEED_CRIT_STREAK`) exactly like every other source that
feeds into them. Active for 24 hours from a player's true first-ever
join -- not first session, so it's still running if they quit after
ten minutes and come back later today, covering the highest-leverage
retention moment there is without becoming a semi-permanent buff.
`NewPlayerLuckIndicator.client.luau` shows a small badge with an honest
countdown the whole time it's active ("🍀 New Adventurer's Luck --
23h 41m left") -- disclosed on purpose, since a real, benefit-only
deadline is a legitimate reason to come back today and hiding it would
only make the crits that follow feel like unexplained luck instead of
a confirmed, trustworthy pattern.

**Server-authoritative, same trust model as everything else that
crosses the client/server boundary in this codebase:** `FirstJoinAt`
is stamped exactly once, server-side, in `PlayerDataHandler.server.
luau`'s `loadPlayerData` -- and specifically only when a DataStore
fetch SUCCEEDS and finds nothing (a fetch that merely FAILS is never
treated as "brand new," or a returning player could get misidentified
on top of everything else going wrong that attempt). Existing saves
that predate this field are never affected: an old save's `FirstJoinAt`
sits at the template's default 0 too, which is exactly why eligibility
is tracked separately during load rather than inferred from "is
FirstJoinAt still 0" -- that shortcut would have misidentified every
already-existing player as brand new the first time each of their
saves loaded after this shipped. Both `CriticalsController` (the real
bonus) and the indicator read a single mirrored `NewPlayerLuckExpiresAt`
attribute, never `PlayerData` directly, so the two can never drift out
of sync with each other.

## 39. Zones -- pick a zone, lean into an essence type, watch it actually look different

Requested directly: a picker that lets a player choose which "zone"
they're collecting in, where new zones cost essence to unlock, each
zone weights the complete Earth/Shadow/Solar catalog differently (all
three retain a non-zero trace chance in every zone), and the split is
amplified by relevant gamepasses. Switching zones plays a travel
animation. All of it new; nothing existing was restructured to build
it -- `EssenceOrbController`'s HP/click mechanics are completely
untouched, there's still exactly one orb to click. A zone is a reskin
of the same click loop with a different essence-type roll under it,
not a second physical map.

**Three zones, live now, in `ZonesConfig.luau`:**

| Zone | Cost / gate | Base weights → with Dedicated Essence |
|---|---|---|
| 🌍 Earthen Grove | Free | 81 Earth / 18 Shadow / 1 Solar → 92 / 7 / 1 |
| 🌑 The Shadowfen | 300 Earth | 17 Earth / 82 Shadow / 1 Solar → 7 / 92 / 1 |
| ☀️ The Sunforge | Rebirth 4; 500K Earth + 25K Shadow | 15 Earth / 15 Shadow / 70 Solar → 6 / 6 / 88 |

Switching between zones you already own is free and unlimited --
only the first unlock of a paid zone ever costs anything, and
unlocking one also travels you there immediately (you almost
certainly want to go there right after paying for it).

**Wires up a real, already-purchasable Game Pass that used to do
nothing.** Section 0 at the top of this file used to flag "Dedicated
Essence" (id `1907077899`) as one of three Game Passes that took
real Robux and then did nothing at all -- explicitly left unfixed
originally because guessing what a paid feature should do isn't a
call to make unilaterally. This one was a direct match: the request
itself asked for gamepass-amplified zone odds, and "Dedicated
Essence" sharpening whichever zone you're standing in toward its
specialty is about as close to its own name as a guess can get, with
zero downside for anyone who already bought it -- it did nothing
before, it does something on-brand now. (The other two, Lucky Finder
and Ultra Luck, are wired up too now -- see section 40.)

**New files:**
- `ZonesConfig.luau` (Shared) -- zone data (name, icon, cost, base and
  amplified weight tables) plus every shared helper used below, so names,
  costs, and odds cannot drift between systems.
- `ZoneService.server.luau` -- the only thing that actually unlocks or
  switches a zone. Same `RemoteFunction` returning `(success, message,
  result)` convention `WheelService`'s `SpinFunction` already
  established, deducting currency the exact same way
  `TreeUpgrades.PurchaseUpgrade` already does (the leaderstat's
  `Quantity` attribute directly, never `PlayerData` first).
- `GetEssence.luau` (Shared, **edited**, not new) -- the actual
  complete essence roll now reads `ZonesConfig.GetEssenceWeights(player)`
  instead of a flat, everyone-gets-the-same 50/50 table. `GetOddsText`
  (the "1 in N" text on a first discovery) now takes the player too, so
  it can never show odds that don't match what they're actually zoned
  into -- `CursorCollection.client.luau`'s two call sites were updated
  to pass it.
- `ZonePanel.client.luau` -- the picker. Prefers the Studio-authored
  navigation button and builds a fallback in the same slot only if that
  entry point is missing. Shows every zone's lock state, live-updating
  cost/odds, and plays the travel animation only after the server
  confirms a switch actually happened, never optimistically on click.
- `ZoneAmbience.client.luau` -- a persistent, subtle glow behind the
  great orb, tinted to whichever zone is current, so a zone actually
  looks different for as long as you stay there, not just for the
  few seconds the travel animation plays. Its glow remains an additive
  sibling behind `LargeOrb`, and it deliberately leaves `ImageColor3`
  alone because several existing effects already animate that property.
  The configured zone orb art itself does swap: Grove restores the captured
  Studio image, Shadowfen uses the uploaded Shadow orb, and Sunforge uses
  the uploaded Solar presentation. It remains more understated than
  PrestigeAura's own aura and sits behind it (lower ZIndex), so the two
  never visually compete.

**Self-review caught two things before committing:** the odds preview
for a zone you're NOT currently standing in originally always showed
its base (non-amplified) numbers, even for a player who owns Dedicated
Essence -- technically true only for the active zone, understating
every other card. Simplified to "amplified if owned, for every card,
regardless of which one is active" -- both simpler and more honest,
since the bonus follows the player, not a specific zone. Separately,
the zone card list's scrolling area originally overlapped the status
message strip at the bottom by a few percent -- caught on a layout
re-read, not a runtime test; shrank the list's height to leave clear
room.

**Corrected after shipping:** `ZonesButton` was originally documented
as living directly under `MainGui.Right`, matching where
`ManualSummonButton` already sits -- the actual location is one level
deeper, `MainGui.Right.Holder`, the same subfolder
`UIInitializerHooks.client.luau`'s own nav-bar block iterates. The
lookup accepts either a raw GuiButton or that folder's usual Frame
wrapper, and now creates a code-owned fallback if neither resolves.

**Added afterward: the Shadowfen has its own orb image.** The
Shadowfen zone entry in `ZonesConfig.Zones` now carries
`OrbImage = "rbxassetid://106130917603943"`; `ZoneAmbience.client.luau`
swaps `LargeOrb.Image` to it the moment `CurrentZoneId` changes to
`shadow_zone`, and back to whatever `LargeOrb.Image` actually was at
load (captured once, not a second hardcoded guess) for Earthen Grove.
Confirmed nothing else in the codebase ever assigns `LargeOrb.Image`
(unlike `ImageColor3`, which is genuinely contested -- see this file's
own header), so there's no fight to sidestep the way the glow layer
has to for color. Can't be tweened/crossfaded -- Roblox has no
interpolation between two asset ids -- so it's an instant swap, timed
to land right as the travel veil starts covering the screen since both
react to the same attribute at roughly the same moment.

**Removed: an old, abandoned `ZonesPopup` scaffold.** While tracking
down a reported UI overlap, found `src/StarterGui/EssencePopupUI/
PopupHolder/ZonesPopup/` -- a pre-existing, unrelated attempt at a
Zones UI (its own `ZonesUIManagement.client.luau`, placeholder-only:
hover/press feel and a cosmetic click ring, explicitly commented "no
real transaction"). Confirmed via the user this was earlier abandoned
work, not something to integrate with -- deleted the whole folder
(all 3 files) rather than leave dead scaffold sitting in the Studio
hierarchy. Nothing else in the codebase ever referenced "ZonesPopup"
by name, and the generic popup-registration/close-button loops in
`UIInitializerHooks.client.luau` iterate `PopupHolder:GetChildren()`
dynamically, so removing it needed no other code changes. The real,
current Zones UI is entirely the `ZonePanel.client.luau` /
`ZoneService.server.luau` / `ZonesConfig.luau` / `ZoneAmbience.client.
luau` set described above -- unrelated to and unaffected by this
removal.

## 40. Lucky Finder + Ultra Luck -- wired to essence rarity, not crit chance

Companion to section 39: "Lucky Finder" and "Ultra Luck" were the
remaining two of the three Game Passes section 0 originally flagged as
pure stubs. **This replaces an earlier guess in this same file that
wired them to crit chance instead** -- reverted in full once their
actual store descriptions were available:

> Lucky Finder: "Increases the base chance of finding rarer essences
> by 50%."
> Ultra Luck: "Stacks with regular luck to give a massive boost
> (x3 luck)."

"Rarer essences" means every catalog entry above Common: Shadow
Essence (Rare) and Solar Essence (Mythic), see `EssenceConfig.luau`.
Both passes multiply every non-common WEIGHT inside
`ZonesConfig.GetEssenceWeights` --
Lucky Finder alone is ×1.5 (its own "+50%" is unambiguous), Ultra Luck
alone is ×2, and owning both multiplies together to exactly ×3 (1.5 ×
2), matching Ultra Luck's own "x3 luck" headline for the stacked case.
Someone who buys only Ultra Luck, skipping "regular luck" (Lucky
Finder), still gets a real, standalone ×2 -- there's no sensible
default that makes an Ultra-Luck-only purchase do nothing just because
the store copy assumes it's bought alongside Lucky Finder.

Living in `ZonesConfig.GetEssenceWeights` (the exact same function
Dedicated Essence's zone-amplification already runs through) means
this is a total no-op for anyone who owns neither pass, applies
regardless of which zone the player is currently in, and both the real
roll (`GetEssence.luau`) and the odds preview (`ZonePanel.client.luau`,
mirrored there since that panel needs to preview every zone, not just
the active one) can never show a number the other doesn't actually
roll against. Multiplying the raw weight rather than solving for an
exact target probability keeps this consistent with how every other
bonus in this system already works -- the resulting chance still
renormalizes against whatever Earth's weight is in the current zone.

## 41. Fixed a real collision: five buttons were rendering on top of MainGui.Right.Holder's own nav bar

Reported directly, with a screenshot: Prestige Shop, Sanctum, Ranks,
Goals, and Group Reward's buttons (all originally at `x=0.895`) were
rendering directly on top of `MainGui.Right.Holder`'s own live nav bar
(Upgrades / Zones / Rebirth / Index / Shop / Settings, wired generically
in `UIInitializerHooks.client.luau`) -- text and icons visibly jumbled
together in the same screen region. This folder's UI properties were
never in this repo to begin with (see "One thing to be careful about"
below), so this was never something a code-only read could have caught
-- the screenshot was the only way to actually see it.

**The fix, as first pushed:** all five moved from `x=0.895` to `x=0.92`,
matching `ProgressionHud`'s Daily/Quest/Codes stack, which the SAME
screenshot showed sitting cleanly to the right of that nav bar.

**Superseded within the hour by an independently-merged fix for the
exact same bug.** The remote branch had diverged -- a separate agent's
PR (#6, "Fix offline EPM baseline and wheel status overlap") had
already been merged with its own fix for this identical collision,
using `x=0.952` and narrower buttons (`0.044` wide instead of `0.062`)
rather than a same-width nudge to `0.92`. Reconciling the two
histories (`git merge`, six conflicts, all in these same `LAYOUT`
tables) kept THEIR values over this session's own `0.92` attempt --
narrower buttons in a dedicated rail is a more deliberate fix than a
same-size nudge that was itself an estimate from a single screenshot,
and theirs had already gone out and presumably been looked at. Same
five files, plus `ProgressionHud.client.luau`'s comment (its own
position was already right in both versions; only the explanation of
why changed, since it's the reason the other five now match it). The
merge also picked up a handful of unrelated, real fixes from that same
PR: a text-overlap bug in `ZonePanel`'s card layout (description/odds
text rendering underneath the action button), matching text-clipping
fixes in `WheelPanel` and `Tutorial.client.luau`, mobile
`UISizeConstraint` fixes on a few banners/cards, and an EPM
(essence-per-minute) baseline bug where an offline-earnings lump sum
could briefly count toward the active-production rate.

**Not fixed, for lack of evidence either way:** the two top-right
badges, 👥 Friend Bonus and 🍀 New Adventurer's Luck (`x=0.985`,
anchored at the RIGHT edge rather than the left, so they extend
further left than they might look -- roughly `0.775` to `0.985`).
Neither was visible in the reported screenshot (0 friends online, and
whatever this save's New Adventurer's Luck state was didn't show the
badge either), so there's no evidence they collide with anything --
but also no evidence they don't, since `Right.Holder`'s actual
vertical extent still isn't known precisely. Worth a specific check
once one of those badges is actually on screen (see item 24 below for
how to force each one).

While auditing this, re-checked every OTHER self-built button/badge
this codebase has for overlaps against EACH OTHER (not just against
Right.Holder) -- Fortune Wheel's floating button (bottom-right corner),
the two top-right badges, and this whole right-edge column all still
have documented, non-overlapping Y ranges. No other collisions found
among anything this code can actually see the position of.

## 42. Multiplayer audit -- does this actually work with several people on one server?

Asked directly: does the game work correctly with multiple people on the
same server? Read every script in `src/Server/` (26 files) plus every
Shared module they depend on for the two ways Roblox multiplayer code
actually breaks: module-scope state that's global to the whole server
process instead of keyed per player, and per-player state that IS keyed
correctly but never gets cleared when someone leaves.

**Short answer: yes, with three real bugs fixed below.** None of them were
about two players interfering with each other's currency or upgrades --
every purchase/reward path in this game (`RebirthShopService`,
`SanctumService`, `ZoneService`, `ProgressionService`, `WheelService`,
`AchievementsService`, `OrbClickManager`, `TreeUpgrades`, `RebirthHandler`,
`EssenceMultiplier`) already keys its state correctly by `player` or
`player.UserId` and never trusts anything the client sends over a shared
remote. The bugs were all about **server-lifetime hygiene**: state that
outlives the player it belongs to, which only ever shows up once real
player turnover happens on a long-running server -- exactly the scenario a
quick single-player Studio test would never surface.

**Fixed:**

1. **`OrbClickManager.server.luau`'s `PlayerDatas` table never cleared on
   `PlayerRemoving`.** It's keyed by `UserId` and only ever lazily created
   (`if not PlayerDatas[userId] then ... end`), so every player who ever
   joined a given server process left a permanent entry behind -- their
   `PlayerData` table plus two leaderstat Instance references, none of it
   ever garbage collected. The bigger problem: a player who reconnects to
   the *same* server process (same `UserId` -- a dropped connection,
   an intentional rejoin) hit that stale, non-nil entry and kept
   reading/writing their OLD, disconnected `PlayerData`/leaderstat
   references for the rest of the session. Nothing crashed -- their
   essence gains just silently stopped showing up anywhere, and never got
   saved, because `PlayerDataHandler` saves off the NEW `PlayerData`
   instance the rejoin created, not the stale one this script was still
   holding. Fixed by clearing `PlayerDatas[plr.UserId]` in the
   `PlayerRemoving` handler that already existed for `comboState`.

2. **`PlayerDataHandler.server.luau` leaked a Folder + 2 IntValues per
   join, forever.** `loadPlayerData` created
   `ReplicatedStorage.PlayerOrbs[UserId]/{Health, MaxHealth}` on every
   single join and never destroyed it on leave -- worse than a Lua-table
   leak, since Instances under `ReplicatedStorage` replicate to and sit in
   memory on every connected client too, not just the server. Confirmed
   dead before removing it: `EssenceOrbController.luau` owns HP entirely
   through attributes now (`OrbCurrentHP`/`OrbMaxHP`), and a repo-wide
   search for `PlayerOrbs` turned up no other reader anywhere, client or
   server. Removed the dead creation code outright rather than just adding
   cleanup for something with zero remaining function.

3. **`StormInitServer.server.luau` only wired new players through
   `Players.PlayerAdded`,** with no loop over `Players:GetPlayers()` to
   catch anyone already in the server -- unlike every other init script in
   this codebase (`GroupRewardService`, `PotionTimerService`,
   `RebirthShopService`, `SanctumService`, `ProgressionService`,
   `LeaderboardService`, `WheelService`, `AchievementsService`,
   `ProductPurchaseHandler` all have this exact loop, specifically for
   Studio script-reload/multi-client-playtest scenarios). Confirmed this
   is the only place `StormController.new` is ever called and the feature
   is genuinely live (client + `ProductPurchaseHandler`'s Essence Rain
   product both reference it) before fixing. In a live server this barely
   matters, since real joins land after scripts finish starting -- but in
   Studio's multi-client Play testing, test players can already be
   registered before this script's `PlayerAdded` connection is made, and
   without this loop they'd silently never get a `StormController` for
   the whole session: no automatic storms, and the manual-summon button
   would just do nothing. Added the same defensive loop every other init
   script already uses.

**Checked and confirmed correct (no changes needed):** every purchase/sync
service (`RebirthShopService`, `SanctumService`, `WheelService`,
`AchievementsService`, `ZoneService`, `ProgressionService`) keys its
debounce/pending-push tables by `player` and clears every one of them in
`PlayerRemoving` -- `ProgressionService` in particular clears nine separate
per-player tables in one function, all correctly. `EssenceOrbController`'s
`orbStates[player]` has an explicit `Cleanup(player)` wired to
`PlayerRemoving` as a backstop. `EPMService.ActiveSessions[UserId]` is set
unconditionally on every join (not lazily, so a rejoin can't inherit a
stale entry) and cleared by `PlayerDataHandler` on leave.
`FriendBonusService` deliberately avoids a per-player cache altogether
(friend counts depend on who ELSE is in the server, so it recomputes
everyone on every join/leave) and guards overlapping recomputes with a
token so a slower stale call can't overwrite a newer one -- a genuinely
good piece of multiplayer-race handling, not something that needed
fixing. `LeaderboardService`'s cross-player snapshot and `EssenceRushService`'s
whole-server event timer are correctly GLOBAL, not per-player, by design.
The core economy math (`RebirthHandler.luau`, `TreeUpgrades.luau`,
`EssenceMultiplier.luau`) holds no module-scope state at all -- every
function takes `player`/`playerData` as arguments and works on exactly
what it's given, which is what makes it safe to share across however many
players are on the server at once.

## 43. Essence Market -- every paid benefit is visible, accurate, and reachable

The old Shop depended almost entirely on Studio-authored presentation, so
the repo could neither guarantee that the entry point existed nor explain
what a player actually received. `MonetizationConfig.luau` now catalogs all
seven permanent passes and six repeatable products with benefit copy that
matches the live implementation. `MonetizationStore.client.luau` builds a
responsive market in code with Featured/Passes/Boosts tabs, product art,
owned/unavailable states, exact benefit details, and player-specific live
prices from `MarketplaceService` -- no guessed or hard-coded Robux prices.
Featured deliberately puts the short starter potion in the first row beside
the strongest permanent conveniences instead of burying every approachable
repeatable offer below all seven passes.

The market never opens Roblox checkout by itself. A player must first open
the market and then deliberately press an offer's BUY button; the existing
server purchase remote still allowlists every id before it can prompt. To
make the catalog discoverable without becoming spammy, at most two optional
interest cards may appear in a session: the first only after 2.5--4 minutes
and the tutorial, the second 5.5--8 minutes later. They wait for other modal
UI to clear, choose among unowned offers with weighted randomness, and only
open the relevant market card. Opening the market once disables the
remaining cards for that session.

The authored Shop button receives a small R$ badge and opens the new market.
If either Shop or Zones is missing from `MainGui.Right.Holder`, a code-created
fallback appears in its expected slot. The rest of the screenshot's
always-on controls were present and correctly placed; Group, Friend Bonus,
New Adventurer's Luck, and manual storm summon remain conditional because
their underlying features genuinely are conditional. Finally, VIP's gold
name/portrait outline now updates immediately after a purchase instead of
waiting for the next join.

## 44. Prophecy Crystal -- temporary futures with a Fate guarantee

The new 🔮 Fate shortcut opens a fully source-built divination chamber:
layered crystal glow, counter-rotating rune rings, moving internal wisps,
twinkling starlight, a faceted pedestal, rarity-responsive colors, and a
server-result reveal that accelerates through false futures before the real
prophecy lands. Rare, Epic and Mythic results escalate through extra rings,
particles, flashes, impact shake and a dedicated callout. The entire frame
and both nested information cards use explicit `UIPadding`, so the long
Mythic benefit line stays clear of the border even on a narrow viewport.
An active-prophecy pill remains beside the shortcut with the exact countdown,
so a player never has to reopen the modal to remember what is running.

Every reading is free and the first is immediately available. The crystal
then reawakens every ten minutes. A roll grants one temporary prophecy for
three to six minutes and replaces the previous one; the catalog spans
Essence multiplier, additive critical chance, rare-Essence weighting, and
hybrid futures. The strongest Mythic reading grants 2x Essence, +20% crit,
and 2x rare-Essence weight for three minutes. Paid luck still stacks with a
prophecy rather than being replaced by the free bonus.

`ProphecyService.server.luau` owns cooldown validation, weighted selection,
effect attributes, expiry and persistence. Both cooldown and active expiry
use Unix timestamps, so leaving does not pause either timer and reconnecting
cannot duplicate a reading. After seven consecutive below-Rare results, Fate
fills and the eighth reading is selected only from Rare-or-better entries;
landing Rare+ at any point resets that meter. `ProphecyConfig.luau` is the
single catalog read by server and client, keeping every displayed duration
and benefit identical to the effect gameplay actually receives.

## 45. Astral visual language -- the premium treatment now reaches the whole game

The Prophecy Crystal and rebuilt Fortune Wheel established a much stronger
visual standard than the older interfaces: luminous layered surfaces,
animated trim, readable inset hierarchy, restrained ambient particles,
reward-specific color, and controls that respond when the player touches
them. `AstralVisuals.luau` now turns that language into one shared client
toolkit instead of copying another several hundred lines of effects into
every panel. It supplies modal shells, raised cards, animated edge gradients,
soft sibling halos, top light rails, corner glyphs, star fields, reveal
sweeps, progress-fill flow, heading shadows, button sheens/ripples and the
upgrade-node constellation treatment from one palette and one animation
loop.

`GlobalVisualPolish.client.luau` applies that toolkit non-destructively at
runtime. This is important because most of the original Upgrades, Inventory,
Index, Rebirth, Settings, Shop and MainGui visual properties exist only in
Studio -- the repository has their controller scripts, not a safe complete
copy of their frames. The pass never changes a frame's Position, Size,
AnchorPoint, visibility contract, price, remote or click handler. It keeps
the authored layout and adds finish around it: each legacy popup receives a
screen-specific shell, title treatment, close-control feedback, nested card
hierarchy and flowing trim; the left HUD currencies/stats and right navigation
receive matching raised surfaces; the manual summon control receives its own
pink relic treatment.

The same decorator understands all of the source-built systems too:
Achievements, leaderboards, Prestige Shop, Sanctum, Zones, progression/daily/
quest/code panels, Group Reward, What's New, offline harvest, tutorial,
potion timers, friend/new-player badges, the Essence Market, discovery and
personal-best banners, Essence Rush, zone travel and the Hollowed One's
framed log. It watches `DescendantAdded`, so offers, quests, leaderboard rows,
daily rewards, potion cards and other runtime clones get exactly the same
finish even when they did not exist during join. Each family retains its own
meaningful accent (green market actions, red rebirth, cyan zones, purple
Sanctum, gold achievements, orange Rush, blood-red Hollowed One) instead of
flattening the entire game into one color.

Upgrades gets the deepest dedicated pass. The viewport now reads as an
"Essence Constellation" with a fixed title, platform-aware drag/zoom/help
instructions, a live zoom percentage and illuminated side rails. Every
tagged node receives a softly breathing aura, a rotating branch-colored
hex orbit and a compact state badge: locked paths dim and show an ×,
available paths accelerate and show +, purchased tiers show their level,
and completed nodes turn gold with a star. All of those react to the existing
`Tier`, `Unlocked`, `Buyable` and category attributes, so the presentation
updates immediately after a purchase or rebirth without inventing a second
source of progression truth.

The upgrade tooltip was also rebuilt where its old implementation could
quietly degrade a long play session. Previously every single mouse-enter
connected one more node attribute listener and one more player listener;
repeated hovering therefore accumulated duplicate callbacks forever. Nodes
now bind once, the current tooltip alone refreshes, removed nodes clean up
naturally, and Rebirths uses one shared listener. The tooltip shows exact
`TIER n / max`, a distinct mastered state, real multiline costs, trimmed lock
requirements and a clear unavailable state instead of displaying the old
fabricated fallback cost of 5. Touch players can tap a node to hold its details
onscreen rather than losing the feature entirely without a mouse. Both copies
of the Studio/cloneable tooltip script remain byte-for-byte identical.

The effects are deliberately budgeted for a Roblox game, not a static mockup.
All decoration is idempotent, removed instances fall out of the registries,
hidden ScreenGuis and invisible panel hierarchies stop animating, and the one
shared animation pass is throttled to 30 updates per second. Existing authored
gradients are preserved rather than stacking a second modifier on top. The
loading screen keeps its separate horror presentation, and Prophecy/Wheel are
excluded from the global decorator because they already are the benchmark and
double-applying the shared effects would only add noise.

## 46. Zone travel is now a real attunement sequence, with exact orb previews

The Zones picker now shows the actual collectible-orb artwork beside every
zone instead of using only a generic colored emoji circle. `ZonesConfig`
owns the shared mapping (`79479049281587` for Earth Essence and
`106130917603943` for Shadow Essence), and each zone declares its specialty
and preview image. The same value feeds its card and full-screen reveal, so
the menu cannot drift away from what the player collects after arriving.
Earthen Grove's central great-orb image remains Studio-authored and is still
restored from the value captured at load; the explicit Earth asset is used
only where a deterministic menu/transition preview is required.

Each card now has a zone-colored pedestal, soft aura, illuminated orbit,
specialty pill and exact orb image. The current zone receives a stronger
resonance state, while opening the picker gives both orbs one finite,
staggered materialization and ring turn. `AstralAccentColor` lets the shared
visual pass honor each card's green/purple identity instead of repainting
both with the panel's generic cyan accent.

Confirmed travel now closes two destination-colored energy gates over the
old scene, blocks click-through, resolves the new orb inside counter-rotating
portal rings, drives an attunement meter through three readable states, and
releases through streaks, rings, motes, flashes and a clean arrival beat.
All delayed work is guarded by a transition token, all movement is finite
TweenService work, and the cinematic still starts only after the server has
accepted the unlock/switch. A rejected or unaffordable request never plays a
fake success transition.

## 47. Essence Storms now feel like the sky has actually opened

`StormVisuals.client.luau` is a new presentation-only director listening to
the existing authoritative `StormStart` / `StormEnd` remote. A storm now
opens a dual-essence eye at the top of the screen, orbiting the real Earth and
Shadow orb art inside counter-rotating runes. A responsive arrival chamber
announces normal or golden weather, then clears so it never hides the drops.
The persistent layer adds a restrained screen grade, charged cloud ceiling,
edge haze, pooled colored energy rain, occasional self-cleaning lightning,
portal pulses and a dedicated subsiding sequence. Buying/forcing more storm
time while one is active gets a separate surge beat instead of replaying the
whole entrance.

Normal storms use a cyan/green/purple dual-essence palette; golden storms
change the entire eye, rain, lightning, flash intensity, particles and audio
to gold/amber/white. The atmosphere root is inactive and cannot consume
input. Twenty-four rain streaks are created once and recycled, lightning is
Debris-cleaned, only three inexpensive rotation tweens persist while the
event is active, and a storm token immediately invalidates stale callbacks
on end. `EssenceStormVisuals` is excluded from the global decorator because
it already owns a complete custom visual language.

The drops were upgraded too: every falling orb now carries a type-colored
aura and counter-rotated comet tail, with sparse cloud-line emission ripples;
crit and golden variants remain visually stronger. The existing active timer
was also using the 300-second cooldown as its denominator, so a fresh
60-second storm incorrectly appeared only 20% full. It now uses the confirmed
duration in the server payload and correctly labels the mixed event
"ESSENCE STORM" rather than "EARTH STORM." Reward math, spawn interval,
orb cap, server collection checks and golden multipliers were not changed.

## 48. Rebirth resets every spendable essence

`RebirthHandler.PerformRebirth` resets Earth, Shadow, and Solar balances in
one server-authoritative transaction. Shadow previously survived in full
while Earth and the upgrade tree reset, creating a prestige loophole; Solar
uses the corrected contract from launch. Rebirth Echo applies consistently to
all three: without Echo they become zero; with its 15% level, every balance
retains 15% (floored). Leaderstat quantities, player attributes, PlayerData,
and saved-EPM baselines are updated together.

`LifetimeShadowEssence` and `LifetimeSolarEssence` deliberately do not reset:
they are permanent earned totals used by Shadow synergy and Solar Radiance.
Purchased Sanctum/Prestige upgrades still survive.

## 49. End-branch upgrades are priced like endgame upgrades now

The late-tree audit found why the most powerful nodes stayed cheap through
eight previous balance passes: most of those passes raised `CostGrowth`, but
growth never runs on a `MaxLevel = 1` purchase. Auto Collection therefore
cost only 1,788, Automation Core 1,544, Manual Storm 1,300, Double Crit 2,438,
and the ultimate +150% Essence Convergence only 8,125. Their prices were
closer to another rebirth than to permanent-feeling branch conclusions.

Tier 0–2 was left completely unchanged so first purchases and midgame routing
keep the pacing already tuned in passes 1–8. Tier 3 gateway ranks received a
smaller tens-of-thousands floor; terminal automation/double-proc/retention
abilities received a 35k–150k floor according to power and effective rebirth
gate; cross-branch capstones now start at 750k. Convergence is the final node
with nine prerequisites and now costs 2.5m. Storm Caller retains its existing
1.61 growth across five ranks, so its 250k opener becomes a 4,023,591 total
endgame sink rather than a 78,460 branch that could be casually cleared.

| Upgrade | Old first price | New first price | New cost to max |
|---|---:|---:|---:|
| Orb Vitality III | 1,880 | 12,500 | 1,558,457 |
| Overload Shots | 1,625 | 35,000 | 35,000 |
| Core Resilience | 1,463 | 50,000 | 50,000 |
| Essence Magnet Field (auto-collect) | 1,788 | 150,000 | 150,000 |
| Critical Chance III | 3,126 | 20,000 | 2,874,249 |
| Double Crit | 2,438 | 150,000 | 150,000 |
| Guaranteed Crit Streak | 5,000 | 50,000 | 942,755 |
| Storm Mastery | 4,376 | 35,000 | 2,532,895 |
| Manual Storm Summon | 1,300 | 125,000 | 125,000 |
| Rebirth Echo | 2,275 | 100,000 | 100,000 |
| Ascension Insight | 5,626 | 75,000 | 2,018,395 |
| Automation Core | 1,544 | 75,000 | 75,000 |
| Twin Orb Manifestation | 9,750 | 750,000 | 750,000 |
| Storm Caller Ascension | 4,875 | 250,000 | 4,023,591 |
| Essence Convergence | 8,125 | 2,500,000 | 2,500,000 |

No effect, maximum level, prerequisite, rebirth gate or early/midgame price
changed. `TreeUpgrades` remains the one source read by both the tooltip and
the server purchase path, so the newly displayed costs are exactly what gets
deducted.

## 50. Solar Essence -- a complete mythic progression layer

Solar Essence is a real third currency rather than an icon pasted onto one
screen. `EssenceConfig.luau` is now the authoritative ordered catalog for
Earth, Shadow, and Solar; collection validation, session leaderstats,
discovery, odds, colors, Index data, HUD rendering, storm pools, tutorials,
quests, and rewards derive from that catalog instead of maintaining separate
two-item allowlists.

Solar is intentionally discoverable before endgame but specialized later:

| Zone | Earth | Shadow | Solar | With Dedicated Essence |
|---|---:|---:|---:|---|
| Earthen Grove | 81 | 18 | 1 | 92 / 7 / 1 |
| The Shadowfen | 17 | 82 | 1 | 7 / 92 / 1 |
| The Sunforge | 15 | 15 | 70 | 6 / 6 / 88 |

The Sunforge unlocks at Rebirth 4 for 500,000 Earth + 25,000 Shadow. Its
mixed cost is validated completely before either balance is touched, so a
failed second-currency check cannot partially spend the first. Lucky Finder,
Ultra Luck, and temporary Prophecy luck amplify both non-common types (Rare
Shadow and Mythic Solar), and the Zones UI previews those exact live weights.
Essence Storm drops now roll against the same current-zone table instead of a
uniform Earth/Shadow list.

Every Solar find permanently builds **Solar Radiance**: +5% global essence
per order of magnitude of lifetime Solar, capped at +50%. The multiplier reads
`LifetimeSolarEssence`, so spending Solar never makes a player weaker. The
spendable balance resets on rebirth alongside Earth and Shadow; Rebirth Echo
retains 15% of all three while every lifetime counter survives.

Solar has several earn paths without becoming a free faucet: normal/storm
orbs, fixed rare Fortune Wheel payouts (20/40/250), a fixed 100-Solar day-7
streak cache, the three-essence discovery milestone, and restrained offline
harvesting after discovery. Solar EPM is bounded to 1–6/min and its second
offline multiplier pass is capped at 2×; this prevents a one-time Wheel/Daily
payout or an extreme late-game multiplier from turning into thousands of
unearned mythic currency overnight.

The existing tree's strongest terminals and capstones are now genuine mixed
currency sinks:

| Upgrade | Solar | Other cost at first rank |
|---|---:|---|
| Overload Shots | 100 | 35K Earth |
| Core Resilience | 150 | 50K Earth |
| Rebirth Echo | 250 | 100K Earth + 2.5K Shadow |
| Automation Core | 250 | 75K Earth |
| Manual Storm Summon | 350 | 125K Earth |
| Essence Magnet Field / Double Crit | 500 each | 150K Earth each |
| Storm Caller Ascension | 750 | 250K Earth + 5K Shadow (rank 1) |
| Twin Orb Manifestation | 1K | 750K Earth + 10K Shadow |
| Essence Convergence | 5K | 2.5M Earth + 50K Shadow |

The Solar counter is created in the existing padded/scrollable currency rail,
and its Index slot is cloned and live-bound even when the Studio-authored GUI
only contains the old two slots. Discoveries, offline rewards, zone cards,
travel, storms, falling orbs, trails, and the great Sunforge orb all use the
same molten-corona presentation through `EssenceVisuals.luau`.

Source art ships at `assets/solar-essence-orb.svg`: transparent 1024×1024 SVG
with corona blades, prominences, plasma orbits, granulation, molten bands, and
a white-hot stellar heart. Its transparent raster export is uploaded as
`rbxassetid://97084886370150`, configured once in Solar's `IconAssetId` field
in `EssenceConfig.luau`. Every surface now resolves that uploaded artwork
automatically. `EssenceVisuals` retains the matching native Roblox UI build as
a fallback if the catalog id is deliberately cleared later.

## 51. Essence Awakening -- the first eight minutes are now a designed journey

New saves no longer fall out of the tutorial into an undirected grind. A
persistent six-beat **Essence Awakening** begins alongside the tutorial,
credits actions the player is already learning, then carries them through a
minute-five power spike and an eight-minute finale:

| Beat | Verified goal | Automatic reward |
|---|---|---|
| First Spark | Collect 3 orbs | 75 Earth |
| Resonant Rhythm | Strike the great orb 20 times | 150 Earth |
| Shape Your Power | Buy any upgrade | 300 Earth |
| Touch the Veil | Find Shadow or reach 25 total collections | 250 Earth + 20 Shadow |
| Read the Current | Roll a prophecy or reach 45 total collections | 500 Earth + 25 Shadow |
| Awakening Rush | Collect 25 orbs after minute 5 | 1,000 Earth + 50 Shadow |

At five active minutes the service turns on a personal 2× essence multiplier.
It uses `FirstJourneyEssenceMultiplier`, independent from potions, Prophecy,
Forge and global Rush effects, so overlapping timers multiply correctly and
cannot erase one another. At eight active minutes, after the route is complete,
the player receives 2,500 Earth, 100 Shadow, 5 Solar and a ten-minute 1.5×
handoff boost. If someone learns slowly, the clock caps at 8:00 and the 2×
rush stays active until their remaining objective is finished; the design
rewards persistence instead of turning the deadline into a punishment.

The clock counts online play only and persists across rejoins. The service
observes the same gameplay remotes and server-written attributes as the real
systems, rate-limits client-fired actions, applies OrbClickManager's collection
validation boundary, advances stages on the server and grants every reward
automatically. The template defaults `Eligible` to false; only
`PlayerDataHandler`'s proven brand-new-save branch flips it true, so veterans
whose older saves receive the merged fields never get misclassified or handed
new-player currency.

`FirstJourneyHud.client.luau` is code-built and intentionally occupies the
lower-center gap above the relic timers rather than adding another right-rail
button or covering the great orb. It waits until the tutorial is completed or
skipped, has real inner padding, a collapsible compass, six milestone pips,
live objective/reward copy, a locally smoothed server clock, stage-specific
colors and sequenced reward effects. Minute five transforms the panel into a
Solar rush state. The finale converges the real Earth/Shadow/Solar icon assets
inside rotating rune rings, reveals the full cache, and hands the player back
to normal play through **Begin Your Ascent**. Fast consecutive completions are
queued, and the finale takes priority, so effects never pile into unreadable
screen noise.

The existing Robux interest-card loop and one-time favorite prompt now respect
this arc too. Eligible newcomers do not receive either during minutes 1–8;
the personalized interest card waits for both journey completion and a clear
modal moment, while the favorite prompt leaves an additional 45-second
breathing gap. Returning players keep their existing timing. This removes two
competing calls-to-action from the most fragile part of the first session
without deleting either conversion path.

The tutorial Skip button also now persists `SeenTutorial = true`. Previously
Skip only hid the current dialogue; the entire tutorial returned after every
rejoin and any follow-up system waiting for tutorial completion remained
blocked.

Creator Hub receives a one-time start event, each stage reach, each retained
minute from 1 through 8, the Rush, completion, and session-exit active time.
Those calls are wrapped and observational only: analytics failure cannot block
the clock, multiplier, save or reward. This makes the next retention pass
answerable from real minute-by-minute drop-off instead of another guess.

## 52. Tutorial buttons unclickable + highlight ring offset -- root-caused and fixed

Reported directly: "during the tutorial, I can't click on any buttons,"
plus the highlight ring appearing offset up. Diagnosed two independent,
concrete bugs while reading through `LoadingScreen.client.luau` and
`Tutorial.client.luau` -- and this branch had ALSO independently
diagnosed and fixed the same two bugs (plus a third, deeper one) by the
time this session's own fix reached the remote, in commits "Make
tutorial overlay click-through," "Restore player-driven frame opening,"
and "Fix modal coordinator button lockout." The merge kept that version
below -- it's a strict superset of this session's own first attempt.

**1. `LoadingScreen.client.luau` fired "done" before it was actually
done.** `LoadingDone`/`PresentationCoordinator.SetReady` -- what
`Tutorial.client.luau` gates its startup on -- used to fire right after
the music fade, a full `CONFIG.FadeTime + 0.1` (~0.8s) *before*
`gui:Destroy()` actually removed the loading screen (a ScreenGui at
`DisplayOrder = 10000`, far above everything else). In that window the
tutorial had already built and shown its fully-interactive dialogue box,
highlight ring, and Next/Skip buttons underneath a screen that hadn't
visually cleared yet. Both this session and the merged branch reached
the identical fix independently: fire readiness only after `gui
:Destroy()`, not before the fade even starts.

**2. The highlight ring's inset math assumed one fixed answer this
codebase already knew not to assume.** `positionHighlight`/
`getFrameCenter` unconditionally added `GuiService:GetGuiInset()`
regardless of whether the TARGET frame's own ScreenGui (`MainGui` or
`EssencePopupUI`) actually ignores the inset -- even though
`OrbClicker.client.luau`/`CursorCollection.client.luau` already
established the correct, defensive pattern for this exact ambiguity
(check `IgnoreGuiInset` live, don't assume). Again, both sides
independently landed on the same fix: `getGuiInsetOffset` now takes the
target frame, walks up to its real ScreenGui ancestor, and skips the
compensation if that ScreenGui also ignores the inset.

**3. The deeper cause of "can't click any buttons": something was
disabling the real orb button's input, not just the tutorial's own
overlays.** This session's first attempt only got as far as suspecting
the tutorial's decorative overlays (the full-screen orb-collect demo,
the highlight ring) and the popup steps' bypass of the real
`_G.PopupUI.Open`/`.Close` system -- routing popup steps through that
system was this session's own fix for the "can't click" report. The
merged version goes further and fixes what was actually the bigger
culprit: `Tutorial.client.luau` now explicitly saves the real orb
`TextButton`'s `Active`/`Selectable`/`Interactable` state up front and
force-restores it to enabled at the start of the orb step (a "modal
coordinator" -- now `PresentationCoordinator.luau`, a new shared
lease/queue module -- could otherwise leave it disabled), and every
decorative element the tutorial itself creates (the demo cursor, ring,
and cloned orb) is explicitly set `Active = false` / `Selectable =
false` / `Interactable = false` so it can never be mistaken for -- or
block -- a real input target. `PresentationCoordinator` also now
arbitrates ALL automatic popups/toasts/tutorials through one
`Acquire`/`Release` lease so only one ever holds the foreground at a
time, which is the more durable fix for a "some button doesn't respond"
class of bug than anything narrower to the tutorial alone could have
been. As a real side benefit that was missed until this pass: the
tutorial's Skip button now also persists `SeenTutorial = true` (it
previously only hid the dialogue, so the whole tutorial came back on
every rejoin).

## 53. Found the actual reason buttons stopped responding game-wide: one fragile chain took down the whole nav bar

After the tutorial-specific fixes in section 52 still didn't resolve "I
can't click on any buttons" on retest, looked past the tutorial entirely
and found the real, much bigger bug: `UIInitializerHooks.client.luau` --
the single script that wires up EVERY nav bar button in the game
(Upgrades, Rebirth, Shop, Settings, Index, Inventory) -- ran that wiring
loop only AFTER an unguarded `WaitForChild`/`FindFirstChild` chain into
`RebirthPopup`'s Studio-authored internals (`Content > Frame >
LargeDisplay > Display > TextLabel`, `CurrentStats`, `Progress`,
`Milestones > Frame`, `Unlocks > Frame` -- none of it captured by git,
per `SYNC.md`'s own note that syncback only captures script-bearing
instances, not UI structure). That chain existed purely to build the
Rebirth popup's live stats display -- a cosmetic detail, unrelated to
whether any button in the game responds to a click.

If ANY of those nested instances was missing, renamed, or simply hadn't
finished syncing into Studio at the moment this script ran, that line
would either hang forever (a bare `WaitForChild` with no timeout) or
throw immediately (chaining `:FindFirstChild()` off a `nil` result) --
and either way, this is a plain top-level script with no error
isolation, so EVERYTHING after that point never ran, including the loop
further down that wires every `MainGui.Right.Holder` button's click
handler. One missing or slow-to-sync instance deep inside one popup's
internals was capable of making the entire nav bar permanently inert,
completely independent of the tutorial, of `PresentationCoordinator`, of
anything either agent's tutorial fix touched.

Fixed by moving the RebirthPopup-specific setup into its own
`task.spawn` + `pcall`, using timed (`10`-second) `WaitForChild` calls
instead of bare ones, with `rebirthUpdates` starting as a no-op that
only gets replaced with the real implementation once the lookup
succeeds. A broken or slow-to-sync RebirthPopup now costs only its own
live stats display (it opens with stale numbers until the background
task finishes, then self-corrects on the next `Rebirths` change or
re-open) -- never the rest of the UI. The nav bar wiring loop, VIP
treatment, and everything else in this script now runs unconditionally
and immediately, with no dependency on RebirthPopup's internal
structure at all.

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
9. **Test Group Reward with a Mundane Studios non-member and member.** A
   non-member should see the new three-card panel and FREE reminder;
   confirm Join opens the right community page. After joining, press
   "I've joined — verify" and confirm the success state appears, then the
   panel/reminder disappear. Essence payouts should rise by 35%, displayed
   crit chance by 5 percentage points, and offline harvest payouts by an
   additional 15%, all without requiring a rejoin (see section 17).
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
17. **Fortune Wheel (section 35)**: click the illuminated 🎡 DAILY
    button in the bottom-right corner. Confirm the padded astral cabinet
    opens without overlapping its title, ticket strip, wheel, prize
    ledger, status or spin control at both desktop and narrow/mobile
    viewport sizes. A fresh account should have its free spin available
    immediately. Confirm the reward pedestals orbit but remain upright,
    the fixed pointer ticks through candidates, all eight odds remain
    visible, and the wheel makes several full turns before landing
    cleanly on the server-selected segment (not a partial/jittery stop).
    The right-side ledger should then become a result chamber whose
    displayed Essence matches the amount actually credited. Click SPIN
    again right after -- it should remain disabled with the countdown
    visible (0 tickets, free spin just used). To see a
    ticket get earned without collecting 60 real orbs, run
    `require(game.Players.YourName.PlayerData).Wheel.CollectionsSinceLastTicket = 59`
    in the command bar, then collect one orb -- a ticket should appear
    and the button should re-enable. To see the JACKPOT segment's
    bigger celebration (extra burst, screen flash) without relying on
    its real 1% odds, temporarily swap `WheelConfig.Segments[8]`'s
    `Weight` to something large (or `WheelConfig.RollSegmentIndex`'s
    return to `return 8` directly). Confirm the Jackpot adds the third
    ring, full particle burst, flash and cabinet shake, then revert the
    temporary test change before shipping.
18. **Biggest Gain (section 36)** needs a session with at least two
    collections of noticeably different sizes to see fire -- the very
    first gain of the session never celebrates (nothing to beat yet),
    it just quietly sets the baseline. Collect normally for a bit, then
    land something bigger (a crit, a Wheel spin, a golden storm hit) --
    the banner should pop in top-center reading "🏆 NEW BEST THIS
    SESSION: +N" and fade out on its own after ~2.5s. Confirm it does
    NOT fire in the first ~7 seconds after joining on a save with
    offline earnings pending (that number belongs to the Welcome Back
    popup, not this).
19. **Tutorial Upgrades step (section 37)** -- on a fresh account, play
    through step 1 normally, then confirm the Upgrades step's essence
    count visibly jumps by +50 shortly after the step begins (the
    starter gift) and that clicking Next does nothing until you
    actually buy an upgrade -- confirm the 10s and 24s hint text and
    fallback Next button show up if you deliberately do nothing. Rejoin
    afterward and confirm you do NOT get a second +50 (the gift is
    one-time via `SeenTutorialStarterGift`, same as every other
    tutorial gate in this file).
20. **New Adventurer's Luck (section 38)** -- on a genuinely fresh
    account, confirm the 🍀 badge appears under the 👥 Friend Bonus
    slot (top-right) showing "+15% Crit Chance" and a counting-down
    "New Adventurer's Luck -- 23h Xm left". Click for a while and
    confirm crits are visibly landing more often than they should on a
    completely unupgraded account. To check the expiry behavior without
    waiting a day, run
    `require(game.Players.YourName.PlayerData).FirstJoinAt -= 90000`
    in the command bar (backdates it past the 24h window), then
    **rejoin** (the attribute is only ever mirrored at load) -- the
    badge should be gone and crits should return to baseline. On an
    account that already existed before this shipped, confirm the
    badge never appears at all, even on the very first load after
    updating.
21. **Zones (sections 39/50)** -- click the authored Zones button and
    confirm Earthen Grove is "📍 HERE", Shadowfen costs 300 Earth, and
    Sunforge shows its Rebirth-4 gate before the 500K Earth + 25K Shadow
    mixed cost. Unlock Shadowfen -- Earth should drop by exactly 300, a
    full-screen travel animation should play, and the panel
    (now closed) should reveal a subtle purple glow behind the great
    orb that wasn't there before. Reopen the panel: Shadowfen now
    reads "📍 HERE" and Earthen Grove reads "TRAVEL". Click TRAVEL
    back to Earthen Grove and confirm the glow turns green again and
    the travel animation plays a second time. Collect a good number of
    orbs in each zone and confirm Shadowfen visibly favors Shadow,
    Earthen Grove favors Earth, and Sunforge favors Solar -- every zone
    should still show trace drops of the other types. To see Dedicated Essence's
    amplified specialty odds without buying the real
    Game Pass, run
    `game.Players.YourName:SetAttribute(1907077899, true)` in the
    command bar and reopen the panel -- every card's odds line should
    sharpen immediately. Then temporarily rename/remove the authored
    `MainGui.Right.Holder.ZonesButton` in a Studio copy and re-run: a
    fallback ZONES button should appear in the same slot and open the
    same panel.
22. **Lucky Finder / Ultra Luck (sections 40/50)** -- open Zones on
    Earthen Grove and note the base line (roughly 🌍 81% • 🌑 18% •
    ☀️ 1%). Run
    `game.Players.YourName:SetAttribute(1907239833, true)` in the
    command bar (Lucky Finder) and reopen the panel -- Shadow's share
    should visibly rise to roughly 25% and Solar remain roughly 1% (×1.5
    doesn't translate to a flat ×1.5 on the displayed percentage once
    the total renormalizes -- see the section's own math). Add
    `game.Players.YourName:SetAttribute(1906063939, true)` (Ultra
    Luck, both now owned) and confirm roughly 59% Earth / 39% Shadow /
    2% Solar. Collect a good number of orbs and confirm the non-common
    types genuinely land more often, not just the
    displayed number changing. Remove both attributes
    (`SetAttribute(id, nil)`) and confirm the odds line and real drop
    rate both return to the un-boosted 81/18/1 split.
23. **Shadowfen orb image (section 39 addendum)** -- travel to the
    Shadowfen and confirm the great orb's actual picture changes (not
    just the ambient glow color) to the configured image right as the
    travel veil covers the screen. Travel back to Earthen Grove and
    confirm it returns to the original orb image exactly -- if it
    doesn't, `LargeOrb.Image` wasn't actually readable at the moment
    this script captured it as the default (a load-order issue worth
    flagging back if it happens, not something the checklist itself
    can fix).
24. **The Right.Holder collision fix (section 41)** -- this is the one
    worth checking most carefully, since it was fixed from a
    screenshot rather than something testable from code alone. Confirm
    Prestige Shop / Sanctum / Ranks / Goals / Group Reward no longer
    overlap Right.Holder's own Upgrades/Zones/Rebirth/Index/Shop/
    Settings nav bar, and separately confirm THIS move didn't create a
    new collision with the Daily/Quest/Codes stack now sharing its x
    column (they're at very different y positions, but that's exactly
    the kind of thing that's obvious in five seconds of actually
    looking and easy to miss by just reading the numbers). Then check
    the two flagged-but-unverified badges specifically: get a friend
    online in the same server (👥 Friend Bonus only appears above 0
    friends) and, separately, check 🍀 New Adventurer's Luck on a
    fresh account (or force it via
    `require(game.Players.YourName.PlayerData).FirstJoinAt = os.time()`
    then rejoin) -- confirm NEITHER overlaps Right.Holder either. If
    one does, its fix is the same one-line move every button in
    section 41 got: shift its `x` in the relevant file's `LAYOUT`
    table.
25. **Essence Market (section 43)** -- open Shop and confirm the new
    market appears alone (the legacy ShopPopup must not open behind it),
    all three tabs render, every card eventually replaces "VIEW OFFER"
    with its live price, owned passes say "OWNED", and BUY opens the
    correct Roblox confirmation. Cancel that confirmation once to verify
    cancellation grants nothing. For the interest-card test, temporarily
    set the first delay to 5--8 seconds in `MonetizationConfig.Spotlights`,
    join with `SeenTutorial = true`, and confirm one card appears only
    while no other modal is open; its button should focus the advertised
    market card but must not open checkout. Restore the real delays before
    publishing. Finally, temporarily rename the authored Shop button in a
    Studio copy and confirm the fallback STORE entry appears.
26. **Prophecy Crystal (section 44)** -- click the large 🔮 FATE shortcut in
    the top-right corner. On a fresh save it should pulse green and
    offer a free reading immediately. Roll once and confirm the outer and
    inner runes counter-rotate quickly, false futures cycle without changing
    the server-selected result, and the final rarity produces rings, motes,
    a readable benefit card and an active countdown pill. Collect while the
    boon is active and confirm its stated Essence/crit/luck effect is real;
    for a luck omen, the Zones odds preview should update immediately too.
    Rejoin during the timer and confirm the same prophecy resumes with less
    time remaining, then expires back to neutral. Roll again immediately and
    confirm the button shows the remaining ten-minute cooldown. To test Fate
    without waiting through seven real cooldowns, set
    `require(game.Players.YourName.PlayerData).Prophecy.RollsSinceRare = 7`
    and `require(game.Players.YourName.PlayerData).Prophecy.NextRollAt = 0`
    in the server command bar, then roll: the meter should announce FATE FULL
    and the result must be Rare, Epic or Mythic. Finally check the padded
    panel at both desktop and phone emulator widths; no title, benefit or
    close control should touch the frame edge.
27. **Whole-game Astral pass (section 45)** -- do one visual circuit on both
    desktop and a narrow phone emulator: open Upgrades, Inventory, Index,
    Rebirth, Settings, Shop/Essence Market, Zones, Sanctum, Prestige Shop,
    Ranks, Goals, Daily, Quests and Codes. Every real panel should retain its
    existing size/position while gaining animated trim, a clear header, raised
    content cards and tactile buttons; no text, icon or close control should
    touch a border or disappear behind a star/sweep. In Upgrades, drag and zoom
    the constellation, verify the live percentage changes, and inspect one
    locked, available, leveled and maxed node. Hover the same node repeatedly
    and rebirth once if possible: the tooltip should update once per change,
    not flicker or multiply callbacks; then repeat with a tap in the mobile
    emulator. Trigger or temporarily shorten a potion, Essence Rush and a
    personal-best/discovery banner to confirm late-created cards receive the
    treatment. Finally open/close the major panels repeatedly for several
    minutes and watch Studio's client performance: hidden panels should not
    keep visibly animating, button clicks should still invoke their original
    actions exactly once, and Output should remain free of new UI errors.
28. **Zone orb cards + attunement travel (section 46)** -- open Zones on both
    desktop and a narrow phone emulator. Earthen Grove must show the green
    Earth collectible, Shadowfen the purple Shadow collectible, and the
    unlocked Sunforge its molten Solar collectible, each with
    its own pedestal/orbit/specialty pill and without touching the card edge,
    description or action button. Travel among all unlocked zones. Confirm the gates
    fully cover every corner, input is blocked only during the cinematic, the
    portal uses the destination's matching orb/color, all three status beats
    and the meter are readable, and controls work again immediately after the
    reveal. Rapidly reopen/close the picker afterward and confirm no stale
    callback hides the HUD or replays an old destination.
29. **Essence Storm spectacle (sections 47/50)** -- use Manual Storm Summon or a
    server-side forced storm. The active bar should start full, say ESSENCE
    STORM, and drain against the real duration. Confirm the storm eye contains
    all three orb presentations, its banner clears quickly, rain/lightning/tint
    do not block any HUD or falling-orb click, and Earth/Shadow/Solar drops use
    current-zone odds with matching aura/tail. End the storm and verify every
    persistent visual fades away. Force another storm while one is already
    active to check the shorter
    SURGE treatment. For golden QA, temporarily force `isGolden = true` in
    `StormController:_startStorm`, confirm the complete gold palette and
    stronger entrance, then revert that temporary test edit. Let one full
    storm run with the mobile performance graph open: pooled streak count must
    stay flat and Output must remain clean.
30. **All-essence rebirth reset (sections 48/50)** -- seed Earth, Shadow, and
    Solar balances. With no Rebirth Echo, perform a real rebirth and confirm
    all three leaderstat quantities and player attributes become 0. Repeat with
    `rebirth_echo` level 1 and confirm all three retain exactly 15% (floored).
    Before/after each attempt, compare every lifetime attribute and a purchased
    Sanctum level: no permanent value may decrease, while all three spendable
    `PlayerData.Essences[*].Quantity` values must match their displayed
    leaderstats after the transaction and after a rejoin.
31. **Endgame price audit (sections 49/50)** -- inspect every Tier 3/4 node in
    the upgrade tooltip and compare it to the table above. Essence Magnet
    Field must show 150K Earth + 500 Solar, Twin Orb 750K Earth + 10K Shadow
    + 1K Solar, and Convergence 2.5M Earth + 50K Shadow + 5K Solar; buying a
    test node must deduct every displayed amount exactly once. Check one Tier 1
    and Tier 2 route as a regression guard—their prices must be unchanged.
    For a leveled late node such as Storm Caller, buy successive ranks and
    confirm the existing growth still advances the price rather than leaving
    every rank at its new base. Finally rebirth and verify the nodes reset as
    before; this pass changes cost only, not the tree's reset contract.
32. **Solar end-to-end (section 50)** -- on a clean account confirm the HUD
    shows a padded Solar row, the Index counts 3 total entries, and Grove odds
    show a 1% Solar trace. Force or wait for a Solar roll: the molten Solar
    orb, MYTHIC SOLAR collection burst, discovery card, leaderstat, Index slot,
    unique count, rarest essence, lifetime attribute, and Radiance multiplier
    should update together. At Rebirth 4, buy Sunforge with both currencies and
    confirm Solar becomes the dominant drop. Claim day 7 and force the three
    Solar Wheel rewards, checking fixed 100 / 20-or-40 / 250 payouts rather
    than rebirth-scaled amounts. Finally rejoin after offline time: Solar may
    pay only after discovery and its saved EPM must remain inside 1–6/min.

33. **Essence Awakening (section 51)** -- use a genuinely fresh DataStore key
    (an old save is intentionally ineligible). Confirm the padded journey card
    stays hidden during the tutorial, appears above the bottom relic bar after
    finishing or skipping, and never covers the great orb or right navigation
    at desktop and phone emulator widths. Complete each goal and verify its
    exact reward lands once; rejoin midway and confirm the same stage, counters
    and active-time clock resume rather than reset or advance offline. At 5:00,
    collect before/after the transition and verify only the latter gain is 2×,
    while an existing potion/prophecy still stacks. At 8:00, confirm the
    Earth/Shadow/Solar convergence finale, exact 2,500/100/5 cache, and
    ten-minute 1.5× potion. Finally, deliberately leave the last objective
    unfinished at 8:00: the clock should hold, the Rush should remain, and the
    finale should fire once the objective is completed. Rejoin after completion
    and confirm neither the HUD nor any reward returns. Also skip the tutorial,
    rejoin, and confirm the tutorial itself no longer comes back.

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
