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

## Good to know

- **"Full hand" means the current hand size.** It follows research
  bonuses and the stack size limit, whether set by hand or by the circuit
  network: with a limit of 2, two items are a full hand.
- **Sparse supply leaves items in the hand.** If fewer items arrive than
  the hand holds, a *Full hand* inserter keeps them and waits. Use
  *Instant* where the last few items must get through, e.g. low-volume
  ingredients.
- **A spoiled hand is dropped right away.** If the items in the hand spoil
  while it waits (say 11 nutrients out of 16 turn into 11 spoilage), the
  inserter stops waiting and drops the spoiled stack instead of holding it
  forever.
- **Stacks on belts need research.** The height of a stack the inserter
  puts on a belt is 1 plus the *transport belt capacity* bonus, capped by
  the inserter's own limit. Before that research, a *Full hand* inserter
  still waits for a full hand but drops items onto a belt one by one.
  Without K2 Spaced Out superior inserters do not stack on belts at all.
- **Early game hands are small.** Without capacity research and without
  K2 Spaced Out the hand may hold a single item, and then both modes
  behave the same.
- **New inserters start in *Full hand*.** That includes ones built from
  the item and upgraded with the upgrade planner. Blueprints and copy-paste
  keep the mode of each inserter.

## Before removing the mod

The *Instant* mode is a separate hidden entity. When the mod is removed,
the game deletes those inserters from the map, like any entity whose mod is
gone. Switch all inserters to *Full hand* first.

## Languages

The mod is translated into English, Russian, German, French, Spanish,
Brazilian Portuguese, Polish, Ukrainian, Simplified Chinese, Japanese and
Korean. Names of inserters follow the game and Krastorio 2 in each
language. Corrections from native speakers are welcome.

## License

MIT for the code of this mod. The thumbnail contains artwork from
Krastorio2Assets (LGPLv3) and Factorio (Wube Software), see
[LICENSE](LICENSE).
