# Tycoon Build System (Roblox, Luau)

Server-side grid building from my tycoon project. Code sample for the Hidden Developers application.

## What it does
- Grid placement with full server-side validation: price, floor limits, per-category rules (floor / wall / surface / ceiling)
- Multi-floor plots: floors unlock via the MaxFloor attribute, elevators clone themselves upward when a floor is bought
- Structural integrity: items stand on a support graph (floor > walls/tables > surface items > ceiling). Remove a support and everything depending on it collapses with an 80% refund
- Save slots via DataStore, compact array serialization to stay far under data limits
- PathfindingModifier tagging so NPCs route around furniture and through doors

## Notes
- The starter base layout (slot 1) is hardcoded in the load handler — in production that lives in a ModuleScript
- Remotes use find-or-create fallbacks for studio testing; in production they're created upfront
- Known next steps: DataStore retry/backoff, placement rate limiting

Author: Corix (Roblox: NekoPeonie) · corixdev.github.io/portfolio
