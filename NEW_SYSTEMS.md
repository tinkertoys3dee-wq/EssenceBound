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
2. **Check the three new buttons** (🎁 Daily / 📜 Quests / 🎟️ Codes) on
   the left edge don't overlap your existing UI. If they do, every
   position is in the `LAYOUT` table at the top of
   `ProgressionHud.client.luau` — one line each, no hunting.
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
