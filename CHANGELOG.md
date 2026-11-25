# Changelog

## 0.3.0

### Added
- **Pawn scales as weights.** With [Pawn](https://www.curseforge.com/wow/addons/pawn) installed, the Weights
  panel gets a **Source** button: click to step through the scales Pawn shows for your character (its
  defaults or your own, a PvP scale for example), right-click to go back to Sugar Daddy's own weights.
  The choice is saved per character.
- While a Pawn scale is the source, the panel shows its name and its numbers read-only; edit them in Pawn
  (`/pawn`) and Sugar Daddy follows straight away, including renamed, imported or deleted scales.

### Notes
- Pawn is optional. Without it Sugar Daddy works exactly as before.
- Only Pawn's numbers are borrowed. Scoring stays Sugar Daddy's: the hit cap, weapon dps share and
  two-hand / dual-wield swaps with what's in your bags.
- Pawn stats Sugar Daddy doesn't weigh (parry, resistances, health, spell penetration) are left out.
- If the picked scale is deleted or renamed in Pawn, Sugar Daddy falls back to its own weights.

## 0.2.0 and earlier

See the [commit history](https://github.com/mutantsan/SugarDaddy/commits/master).
