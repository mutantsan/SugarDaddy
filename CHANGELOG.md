# Changelog

## 0.3.0

### Added
- **Pawn scales as weights.** With [Pawn](https://www.curseforge.com/wow/addons/pawn) installed, the spec menu
  (top left) lists the scales Pawn shows for your character under a **Pawn** heading, its defaults or your own
  (a PvP scale, for example). Pick one and it scores your upgrades. The choice is saved per character.
- While a Pawn scale is picked, the Weights panel shows its numbers read-only; edit them in Pawn (`/pawn`)
  and Sugar Daddy follows straight away, including renamed, imported or deleted scales.

### Changed
- The Spec button is now a dropdown menu. It starts on the spec your talents point to and follows a respec;
  picking another spec pins it. The separate "Automatic" choice is gone.

### Notes
- Pawn is optional. Without it Sugar Daddy works exactly as before.
- Only Pawn's numbers are borrowed. Scoring stays Sugar Daddy's: the hit cap, weapon dps share and
  two-hand / dual-wield swaps with what's in your bags.
- Pawn stats Sugar Daddy doesn't weigh (parry, resistances, health, spell penetration) are left out.
- If the picked scale is deleted or renamed in Pawn, Sugar Daddy falls back to its own weights.

## 0.2.0 and earlier

See the [commit history](https://github.com/mutantsan/SugarDaddy/commits/master).
