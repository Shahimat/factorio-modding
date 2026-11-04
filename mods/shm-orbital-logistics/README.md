# Orbital Logistics

Depots and cargo with a destination for space platforms in Factorio 2.1, on
top of the vanilla platform-to-platform transfers. The mod only decides, for
each item on each hub, whether the hub may give it away in the orbit it is
in. Rockets, cargo pods and transfers stay vanilla.

## A route with and without the mod

**Without the mod (vanilla):** a hub never gives away an item it requests
itself, so a depot filled from the planet cannot serve shuttles. Every
platform requests its own cargo from the planet under it: rockets on every
planet, rocket parts and fuel on every shuttle.

**With the mod:** a depot over Nauvis marked `[depot:nauvis]` is filled by
Nauvis rockets, as before, and gives plates to every shuttle in its orbit.
A depot over Aquilo takes the cargo from arriving shuttles and drops it on
the planet.

Also in the mod:

- `[reserve]` fuel and ammo stays on the platform; `[cargo→aquilo]` is not
  handed out on the way.
- Leave *Import from* empty with a large amount: the platform collects in
  every orbit and delivers only at its destination.
- Supply lines: one item list for a whole chain — depots, shuttles, a
  landing pad — each participant with its own factor.

## Tags

Set tags in the panel next to the hub window, or type them into a group
name yourself:

| Tag | Purpose |
|---|---|
| `[reserve]` | own supply, never given away |
| `[cargo→aquilo]` | cargo for Aquilo, held everywhere else and in flight |
| `[cargo→vulcanus,aquilo]` | several planets: the first one on the route takes what it asks for |
| `[depot:nauvis]`, `[depot:nauvis,vulcanus]` | a depot over these planets, held elsewhere |
| `[depot]` | a depot wherever the platform stops |

Use internal names: `nauvis`, `vulcanus`, `gleba`, `fulgora`, `aquilo`.
Tags are case-insensitive, `->` works as well as `→`. Sections of all kinds
mix on one hub; a group without a tag works as usual.

## Panel

Open a hub: the panel below its window lists the hub's request sections.
Pick a purpose and places, press *Apply*. *Giving in this orbit* shows, per
tagged section, whether it holds its items or gives them here. *Supply
lines…* opens the supply lines window, also `/shm-orbital-lines`. The panel
sits below, above, left or right of the window (*Settings → Mod settings →
Per player*) and can be collapsed. *Tips and tricks* has a page on the mod.

## Troubleshooting: a depot does not give

Check the source of the depot request, then the *Provide to other
platforms* flag on the hub.

| Depot request source | Consequence |
|---|---|
| *Planet* | Fills from the planet below; does not block giving to platforms. Importing from the planet the depot is over blocks dropping onto it — to supply that planet, use *Platforms* or import from another planet. |
| *Platforms* | Never gives such items to platforms in the orbit, even with the request filled. Use it when the depot supplies the planet below. |
| *All* | Both effects: never gives to platforms; when importing from the planet below, never drops onto it. |

Other causes:

- *Provide to other platforms* is off: nothing is given to platforms;
  dropping to the planet is not affected.
- The item is also `[reserve]` on this hub: the reserve part is never
  given away.
- The platform is in flight: cargo and depots are closed while flying.

The panel warns about the source traps and marks affected items in *Giving
in this orbit*; the supply lines window shows the same warnings for the
depot role.

## Good to know

- The mod keeps its own group *⚙ Orbital Logistics — auto #N* on hubs where
  it holds something. Its zero filters are how it blocks giving. Do not
  edit it: it is rewritten every second and removed when there is nothing
  to hold.
- If an item is both reserve and depot on one hub, the depot part is given
  while the hub holds more than the reserve. One large delivery can still
  take some of the reserve: vanilla chooses the size of each delivery.
- The controller goes over platforms in small slices: about 1 ms every 10
  ticks for 40 platforms with 160 filters each in one orbit.

## Removing the mod

Turn off *Enable Orbital Logistics* in the map settings first. The mod then
removes its groups from all hubs and turns cargo sections back on. After
the mod is removed, nothing can undo them.

## Source

Open source, MIT: https://github.com/Shahimat/factorio-modding. Bugs and
ideas are welcome in the mod discussions.
