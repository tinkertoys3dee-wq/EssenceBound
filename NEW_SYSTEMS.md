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

**Found but deliberately not touched:** `root_awakening` levels 2–5 (the
literal first node in the tree) cost up to 428,415 essence and do
*nothing* — its `EffectType = "UnlockTree"` is defined but never read
anywhere in the codebase, despite the in-game description promising it
"doubles base essence reward for each level." Not an early-game issue
(a new player can't reach 195 essence for level 2 for a while), but it's
real false advertising sitting at the root of your upgrade tree and worth
a conscious call: either wire up a real effect, or fix the description.
I didn't want to invent tree-wide balance numbers without being able to
playtest them.

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

### The full upgrade list (11 total)

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

Two new Sanctum purchases that aren't stat bumps — they're timed events
that fire on their own and demand attention when they do:

| Relic | Cost | Interval (lvl 1 → 2) | Effect |
|---|---|---|---|
| 🔨 Shadow Hammer | 500 → 3000 | 45s → 28s | Telegraphed slam on the great orb, +4 → +7 bonus real orbs |
| 🌌 Void Laser | 700 → 4200 | 55s → 32s | Beam sweeps the field, instantly collects everything active |
| ⌛ Chrono Rift | 900 → 5400 | 70s → 45s | 6s → 10s window where collection is instant, no hover charge |

Chrono Rift grants a temporary *state* rather than a one-shot payout, so
for its duration the whole loop plays differently — sweep the cursor and
everything it touches is gathered immediately. It reuses the exact
instant-collect path `essence_magnet_field` permanently unlocks, so the
two can't drift apart, and a full-screen tint makes the altered state
unmistakable.

Both fire through the **exact same functions** a real click/collection
already uses (`SpawnOrb`, `CollectEffect`) — no new trust surface, payout
validated server-side through the identical path everything else uses.

Each gets a **live countdown pill** (top-center, Hammer above Laser) built
into the same loop that fires the ability, ticking in 1-second steps so
display and timing can never drift apart. Positions are one-line moves —
`HAMMER_PILL_POSITION` in `OrbClicker.client.luau`, `LASER_PILL_POSITION`
in `CursorCollection.client.luau`.

### Panel layout

With eleven upgrades the list needed real structure:

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
`Levels[level] = {Interval, BurstCount?/WindowSeconds?}` was the only
change needed —
`SanctumService` and `SanctumPanel` already read costs/levels/
descriptions generically, so the whole server + panel pipeline picked
these up with zero changes to either file.

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

## What to check when you open Studio

1. **Press play and confirm essence actually goes up.** This is the whole
   ballgame. Click the orb, hover a drop, watch the counter. If it moves,
   the core bug is fixed.
2. **Check the four new buttons** (🎁 Daily / 📜 Quests / 🎟️ Codes /
   🌑 Sanctum) on the left edge don't overlap your existing UI. Positions
   live in the `LAYOUT` table at the top of `ProgressionHud.client.luau`
   and `SanctumPanel.client.luau` — one line each, no hunting.
3. **Try a code** (`LAUNCH`) to confirm the redeem flow works end to end.
4. **Watch the Output window** for red errors on join.
5. **Daily panel auto-opens** on a first join once the tutorial is done.
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
