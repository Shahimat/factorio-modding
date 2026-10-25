# Advanced Belts

Four belt tiers beyond turbo for Factorio 2.1 Space Age, each with a
transport belt, an underground belt, a splitter and, with
[AAI Loaders](https://mods.factorio.com/mod/aai-loaders), a loader:

| Tier | Speed, items/s | Underground | Resources | Research |
|---|---|---|---|---|
| Superior | 90 | 15 | holmium plates, supercapacitors | electromagnetic science |
| Ultra | 105 | 19 | carbon fiber, processing units | agricultural science |
| Hyper | 135 | 23 | lithium plates, quantum processors | cryogenic science |
| Absolute | 150 | 27 | biter eggs, speed modules 3 | promethium science |

Each tier is made from the previous one, starting from turbo, plus
lubricant. Recipes work in assemblers and in the foundry — and in any other
machine that crafts `metallurgy`, on any surface. The upgrade planner goes
turbo → superior → ultra → hyper → absolute.

The mod is pure Space Age: it does not depend on Krastorio 2 or on planet
mods. Planet mods can retune it through the API below.

## Settings

All settings are startup settings.

- **Per tier:** enabled, speed, underground length. Speeds are multiples
  of 15: the game stores belt speed in steps of 1.875 items/s, so only
  those are whole numbers. A disabled tier is skipped — the next tier is
  made from, researched after and upgraded from the previous enabled one.
- **AAI loader price divisor** (default 5). In the *expensive* mode of AAI
  Loaders every ingredient of every AAI loader recipe — AAI's own, this
  mod's and other mods' — is divided by it, rounded up. The previous loader
  in a recipe is not divided. Recycling follows the new recipes. The
  *lubricated* mode is not affected.
- **AAI loaders in belt technologies** (off). Every AAI loader — AAI's own
  tiers, this mod's and other mods' — is unlocked by the technology of its
  belt, found by the loader recipe, and the separate loader technologies are
  hidden. In the *lubricated* mode a loader may unlock before lubricant; it
  stays idle without it, like any AAI loader.
- **Belt stacking for all loaders** (on). Every loader can put stacks on
  belts; the stack size is set in its window. When off, the mod leaves
  stacking alone and AAI Loaders uses its own setting.
- **Full stack mode for loaders** (on) and **new loaders wait for a full
  stack** (on). A loader in *Full stack* mode puts items on the belt only as
  full stacks; *Instant* puts whatever it has. Switch a loader by hovering
  it and pressing `SHIFT + M` (rebindable in Controls) or with the switch
  to the right of its window. The mode is kept in blueprints and copied with
  entity settings.

## Good to know

- **Stacks need research.** A loader puts stacks as high as the *transport
  belt capacity* bonus allows, or as set in its window. Before that research
  both modes put single items.
- **Sparse supply waits.** A *Full stack* loader holds back the last items
  until a full stack is there. Use *Instant* where the last few items must
  get through.
- **Biter eggs spoil and hatch.** The absolute tier costs biter eggs, which
  hatch into biters when they spoil.

## For mod authors

Add `? shm-advanced-belts` to your dependencies and call the API in your
`data.lua`:

```lua
if ShmAdvancedBelts then
  ShmAdvancedBelts.set_enabled('ultra', false)
  ShmAdvancedBelts.configure('hyper', {
    speed = 120,
    color = { 0, 200, 120 },
    recipes = {
      belt = { ingredients = { { type = 'item', name = 'my-plate', amount = 5 } } },
    },
    technology = { count = 3000, prerequisites = { 'my-planet-science-pack' } },
  })
end
```

Tier keys: `superior`, `ultra`, `hyper`, `absolute`. Fields: `enabled`,
`speed` (items/s), `color`, `recipes` (`belt`, `underground`, `splitter`,
`loader`, `loader_expensive`), `technology`, `loader_technology`. Values set
through the API win over player settings. To lock a setting instead, do it
in your `settings-updates.lua`: a bool setting with `forced_value` and
`hidden`, a number setting with `default_value`, a single-value
`allowed_values` and `hidden`.

## Before removing the mod

The non-default loader mode is a separate hidden entity. When the mod is
removed, the game deletes loaders in that mode from the map, like any entity
whose mod is gone. Switch all loaders back to the default mode first.

## Languages

English, Russian, German, French, Spanish, Brazilian Portuguese, Polish,
Ukrainian, Simplified Chinese, Japanese and Korean. Corrections from native
speakers are welcome.

## License

MIT for the code of this mod. The graphics are masks derived from Factorio
turbo belt sprites (Wube Software), see [LICENSE](LICENSE).
