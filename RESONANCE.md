# Resonance gameplay loop

Resonance rewards deliberate collection instead of only raw click speed.

## The loop

1. **Alternate Earth and Shadow Essence** within six seconds to build up to
   12 Harmony. Repeating the same type breaks the chain. Each stack adds 8%
   essence, up to a 1.96x skill bonus.
2. Every valid collection fills the **Pulse meter**; criticals fill it faster.
   At 100 Pulse, press **Activate** for 15 seconds of 2x Overdrive.
3. Collecting during Overdrive extends it slightly, up to 22 seconds. This
   creates a decision between activating immediately and saving a full meter
   for a dense storm.
4. Collections also grant permanent **Resonance Mastery XP**. Its 25 levels
   each add a 2% passive essence bonus and persist through rebirths.

All reward-bearing state is owned by `ResonanceService` on the server. The UI
only requests activation and renders server snapshots. Collections enter the
system after `OrbClickManager` has validated their type and quantity.

## Balance knobs

All durations, caps, gains, mastery XP requirements, and multipliers live in
`src/Shared/ResonanceConfig.luau`. The mirrored constants in
`EssenceMultiplier.luau` are intentionally clamped server-side as a final
trust boundary; update those caps if the configuration's maximums change.
