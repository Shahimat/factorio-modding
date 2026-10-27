# Orbital Logistics

Depots and cargo for space platforms in Factorio 2.1, on top of the vanilla
platform-to-platform transfers. The mod does not move anything itself:
rockets, cargo pods and transfers stay vanilla. It only decides, for each
item on each hub, whether the hub may give it away in the current orbit.

## Tags

A purpose is set per logistic section by a tag in the name of its logistic
group. The tag travels with the group to every hub, survives blueprints and
copy-paste, and is typed in the vanilla hub window.

| Tag | Purpose |
|---|---|
| `[reserve]` | own supply: fuel, ammo, repair packs — never given to other platforms or dropped to the planet |
| `[cargo→aquilo]` | cargo for Aquilo: held in every other orbit and in flight |
| `[cargo→vulcanus,aquilo]` | cargo for several planets: the first one on the route takes what it asks for |
| `[cargo]` | plain vanilla cargo, same as no tag |
| `[depot:nauvis]`, `[depot:nauvis,vulcanus]` | a depot: serves other platforms in its orbits, held elsewhere |
| `[depot]` | a depot in any orbit where the platform stops |

Example: a group named `Plates to Aquilo [cargo→aquilo]`. Use internal
location names: `nauvis`, `vulcanus`, `gleba`, `fulgora`, `aquilo`. Tags
are case-insensitive, `->` works as well as `→`. Sections without a tag are
left to vanilla.

One platform can carry any mix of tagged sections: ten depot sections, ten
reserve sections and ten cargo sections on one hub is fine, and a flying
depot is just `[depot]`.

## How it works

- A depot is filled by vanilla: request the items from the planet. It gives
  to platforms that request from platforms, and drops its surplus over
  *max* to the planet as vanilla does.
- Cargo brought for the depot's orbit by other platforms goes to the depot:
  while such cargo is in the orbit, the mod adds a request from platforms for
  what the depot is missing, and the depot holds the item until that is done.
- Cargo collected with an empty *import from* is given away at its
  destination: there the mod turns its section off on that hub, and back on
  when the platform leaves.
- If an item is both reserve and depot on one hub, the depot part is given
  while the hub holds more than the reserve. One large delivery can still
  take some of the reserve: vanilla chooses the size of each delivery.
- The *Provide to other platforms* checkbox keeps its vanilla meaning: off
  means no giving to platforms; dropping to the planet is not affected.

The mod keeps its own section without a group on each hub it manages. Do not
edit it: it is rewritten every second.

## Removing the mod

Turn off *Enable Orbital Logistics* in the map settings first. The mod then
removes its sections from all hubs and turns cargo sections back on. After
the mod is removed, nothing can undo them.
