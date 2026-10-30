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

## Panel

Open a hub: the panel below the window shows every request section with a
purpose list and a location picker: pick places with «+», click a picked
place to remove it. A cargo section the mod turned off at its destination is
marked *(off until departure)*. *Tips and tricks* has a section on the mod. *Apply* writes the tag into the group
name, so it applies to every hub in that group. *Giving in this orbit* shows one line
per tagged section — whether it holds its items or gives them in this orbit —
and the exceptions below, such as a depot taking brought cargo. A red warning appears when *Provide to other platforms* is off
while the hub has a depot or cargo with a destination. The panel can sit
below, above, left or right of the window: *Settings → Mod settings → Per
player*.

## Supply lines

A supply line is one list of items for a whole chain: a depot over Nauvis,
the cargo platforms, the depot over Aquilo and the landing pad on Aquilo.
Open the window with `/shm-orbital-lines` or *Supply lines…* in the panel,
create a line and add items. Attach hubs and landing pads from the panel next
to their windows, then set each participant's role, locations, import
location, source and factor. *Apply* keeps one logistic group per role and
source on the participants, each with its own factor: change rare to
legendary or 2000 to 3000 once, and every participant follows. Sections of a
line are read-only in the hub panel. Manual sections stay as they are.

## How it works

- A depot is filled by vanilla: request the items from the planet. It gives
  to platforms that request from platforms, and drops its surplus over
  *max* to the planet as vanilla does.
- Cargo brought for the depot's orbit by other platforms goes to the depot:
  while such cargo is in the orbit and the depot is short, the mod lets the
  depot take from platforms, up to its own request and no more, and the
  depot holds the item until that is done.
- Cargo collected with an empty *import from* is given away at its
  destination: there the mod turns its section off on that hub, and back on
  when the platform leaves.
- If an item is both reserve and depot on one hub, the depot part is given
  while the hub holds more than the reserve. One large delivery can still
  take some of the reserve: vanilla chooses the size of each delivery.
- The *Provide to other platforms* checkbox keeps its vanilla meaning: off
  means no giving to platforms; dropping to the planet is not affected.

While it holds something on a hub, the mod keeps its own group *⚙ Orbital
Logistics — auto #N* there with zero filters. Do not edit it: it is rewritten
every second, and removed together with the group when there is nothing to
hold. The mod goes over platforms in small
slices, a full round every second, and handles a platform right away when it
arrives or departs.

## Removing the mod

Turn off *Enable Orbital Logistics* in the map settings first. The mod then
removes its sections from all hubs and turns cargo sections back on. After
the mod is removed, nothing can undo them.
