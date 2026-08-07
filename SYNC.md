# How to sync

Two directions. Pick the one you need.

Branch: `claude/retention-and-captivation`
Project folder: wherever you run `git` from (`C:\RobloxGame` or `C:\Users\bgebh`)

---

## A. GitHub → Studio (getting new code into your game)

**The order matters.** Connect first, pull second. Doing it the other way
round makes Studio overwrite the code you just downloaded.

### 0. Backup

Studio → File → Save As → `EssenceBound-backup.rbxl`

### 1. Clean the working tree FIRST

```powershell
git status
```

If anything is listed, deal with it before going further — a dirty tree is
what makes `git pull` abort with *"local changes would be overwritten"*.

- **Want to keep those edits?**
  ```powershell
  git add -A
  git commit -m "describe the change"
  git push origin claude/retention-and-captivation
  ```
- **Don't want them?**
  ```powershell
  git checkout -- .
  ```
  (throws them away permanently)

### 2. Connect Argon

```powershell
argon serve
```

Studio → Argon panel → gear icon:
- **Initial Sync Priority → Client** (Studio wins)
- **Two-Way Sync → ON**

Connect.

✅ The dialog must say **0 removals.** Additions/updates are fine.
❌ If it wants to remove things, **Cancel** — see Troubleshooting below.

### 3. Now pull, with Argon still connected

```powershell
git pull origin claude/retention-and-captivation
```

Each changed file is picked up as a live edit and pushed into Studio.

> If a text editor opens asking for a merge message: press `Esc`, type
> `:wq`, press Enter. (Avoid this in future with
> `git config --global core.editor notepad`.)

### 4. Verify, then publish

Check Explorer for what you expect, watch Output for red errors, then
**File → Publish to Roblox**.

---

## B. Studio → GitHub (saving your own edits)

With Argon connected and Two-Way Sync ON, Studio edits are already written
to disk. So it's just:

```powershell
git status          # confirm your files are listed
git add -A
git commit -m "describe what you changed"
git push origin claude/retention-and-captivation
```

⚠️ **Only scripts sync this way.** The syncback captures script-bearing
instances only — every `.meta.json` in this repo is bare `{"className":
...}` with no properties. If you added Frames, TextLabels, buttons, or
changed positions/properties in Studio, **they will not appear in git**.
That's why `MainGui.Left` and `Healthbar` aren't in this repo.

If `git status` shows nothing after a Studio edit, that's why.

---

## Troubleshooting

### "local changes would be overwritten by merge"

You skipped step 1, or Argon wrote Studio's copy back to disk while
connected. `git status` to see what, then commit it or
`git checkout -- .` to discard.

### The sync dialog wants to remove things

It's trying to delete instances that exist in Studio but not in the repo —
the `Remotes` folder, `PlayerOrbs`, `PotionRemotes`, all your UI. Losing
`Remotes` alone breaks the whole game.

Cancel. Then make sure **Initial Sync Priority = Client** so Studio wins
the initial reconciliation, which is what keeps removals at 0.

### I want the repo's version of one specific file to win

While Argon is connected:

```powershell
git checkout -- src/Server/ProductPurchaseHandler.server.luau
```

Rewriting the file on disk registers as a live edit, so the repo's version
gets pushed into Studio — handy when Studio has a stale copy of one script.

### A new script didn't appear in Studio

Check `default.project.json` maps the service it belongs to:

| Folder | Studio location |
|---|---|
| `src/Shared` | ReplicatedStorage |
| `src/Server` | ServerScriptService |
| `src/Client` | StarterPlayer → StarterPlayerScripts |
| `src/ServerStorage` | ServerStorage |

Services removed from that file are not synced at all. `StarterGui` is
deliberately left out — see the warning in section B.

---

## Why it's this awkward

The repo doesn't contain a complete copy of the game: the original Argon
syncback only captured scripts, not UI instances or properties. So a
straight filesystem→Studio sync would delete everything the repo doesn't
know about.

Working around it means letting Studio win the initial sync, then feeding
changes in as live file edits.

To fix it properly: enable property syncback in Argon's settings, do a
full Studio→filesystem syncback, and commit that. Then the repo would hold
the real game and this dance stops being necessary.
