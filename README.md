# CrabTastyMod

> **Work in progress.** The goal is to replace the TastyOrange perk's default behavior with a Collector-style bonus that scales off weapon mods instead of perks.

## What it does

TastyOrange normally gives a flat damage bonus. This mod repurposes it using the **Collector** perk type (ID 72), whose built-in C++ formula is:

```
damage_bonus = BaseBuff × perkCount
```

Since there is no native perk type for "count weapon mods", the mod tricks Collector's formula by rewriting `BaseBuff` every 500 ms so the result comes out to `weaponModCount × 3%`:

```
BaseBuff = (weaponModCount × DAMAGE_PER_MOD) / perkCount
```

The net effect: TastyOrange grants **+3% damage per weapon mod owned** instead of its default behavior.

The DataAsset change is process-local — no other players are affected.

## Requirements

- **Crab Champions** (Steam)
- **Windows 10 or 11**
- UE4SS is bundled — no separate install needed

## Installation

Copy the contents of `client/` into your game's `Win64/` folder:

```
<GameRoot>\Crab Champions\Binaries\Win64\
```

## License

MIT — see [LICENSE](LICENSE)
