# Changelog

## 0.5.0

### Added
- Slots in the list can be collapsed.
- A clicked item stays highlighted while you look at others.

### Changed
- Simpler status line and tooltips.

## 0.4.0

### Added
- **Shop for another character.** A new menu left of the spec menu picks whose gear you shop for: yourself or
  any of your characters on this realm and faction. Shop from a bank character, then mail the loot to your main.
  Scores use that character's class, level, talents, gear, bags, stats and hit, as it last saw them.
- Each character leaves a snapshot when it logs in, and the snapshot updates as its gear, bags, level or talents
  change. A character shows up in the menu once it has logged in with Sugar Daddy.
- The menu's tooltip says how old the snapshot is. **Forget a character** removes one.

### Changed
- The spec, Pawn scale and level range now belong to whom you shop for, so each character keeps its own. Your
  current choices carry over.
- Switching characters clears the list; scan again for the new one.
- While shopping for someone else, the auction house's "usable only" filter is off (it goes by the logged-in
  character); Sugar Daddy checks class and armor itself.

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
