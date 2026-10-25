# Krastorio2: Superior Inserters Full Hand Switcher

Krastorio 2 superior inserters are bulk inserters, and with K2 Spaced Out
they also stack items on belts, but they drop whatever they grabbed without
waiting for a full hand. This mod makes them wait for a full hand by
default, like the Space Age stack inserter, so belts get full stacks.

Each inserter can be switched between two modes:

- **Full hand** (default) — waits until the hand is full, then drops;
- **Instant** — drops right away, as in Krastorio 2 without this mod.

How to switch:

- hover the inserter and press `SHIFT + M` (rebindable in Controls);
- or flip the switch to the right of the inserter window. With
  [Change Inserter Drop Lane](https://mods.factorio.com/mod/ChangeInserterDropLane)
  installed, it sits right below its drop lane switch.

The mode is kept in blueprints and copied with entity settings. Both modes
are built from the regular superior inserter item. Ghosts cannot be
switched — they take the mode from the blueprint. A tip in *Tips and
tricks → Inserters* explains the controls.

Works with the superior inserter and the superior long inserter. Requires
Factorio 2.1 and Krastorio 2; K2 Spaced Out is optional.

## Before removing the mod

The *Instant* mode is a separate hidden entity. When the mod is removed,
the game deletes those inserters from the map, like any entity whose mod is
gone. Switch all inserters to *Full hand* first.

## License

MIT for the code of this mod. The thumbnail contains artwork from
Krastorio2Assets (LGPLv3) and Factorio (Wube Software), see
[LICENSE](LICENSE).
