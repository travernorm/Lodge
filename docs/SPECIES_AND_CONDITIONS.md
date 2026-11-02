# Species and conditions (Central Oregon)

**Status: draft design target, from Traver's brainstorm on 2026-11-02.** This is the palette of fish, hatches, seasons and weather for Traver's own Central Oregon rivers. It feeds [FISH_LOGIC.md](FISH_LOGIC.md) (generation, mood, take) and [ARCHITECTURE.md](ARCHITECTURE.md) section 3.9 (conditions). Nothing here is in the game yet: each field reaches `FishSpecies`, `Season`, `Hatch` or the `Clock` through its own REQ, when the system that reads it is built.

Eighteen Central Oregon species to stock your own rivers with. Each one is described by the kind of water and conditions it wants, not by a real river, so any river you design can place them.

## Calendar, time of day and temperature

The game year is **four 30-day seasons**, and anything seasonal (hatches, spawning, runs, stocking) is set by season and day, such as "Spring 25 to Summer 10". Each season stands in for three real months, so ten game days is about one real month.

| Season | Days 1 to 10 | Days 11 to 20 | Days 21 to 30 | Air temperature (daily high) |
| --- | --- | --- | --- | --- |
| Spring | early spring | mid spring | late spring | 40s to 60s |
| Summer | early summer | midsummer | late summer | 70s to 90s, 100s in a heat wave |
| Fall | early fall | mid fall | late fall | 50s to 70s |
| Winter | early winter | midwinter | late winter | 30s to 40s |

**Six time slots** split each day. The hours are a proposal so the clock can map onto them.

| Slot | Hours | Air temperature |
| --- | --- | --- |
| Dawn | 5 to 7 | Day's high minus 2 bands |
| Morning | 7 to 11 | High minus 1 band |
| Noon | 11 to 14 | The day's high |
| Afternoon | 14 to 18 | The day's high |
| Dusk | 18 to 20 | High minus 1 band |
| Night | 20 to 5 | High minus 2 bands |

**Temperature comes in eight 10°F bands:** 30s, 40s, 50s, 60s, 70s, 80s, 90s, 100s. Each day rolls its high band from the season's range, and the slots step down from it, which gives the big high-desert swing between a cold dawn and a hot afternoon.

**Water temperature** is what fish actually feel, so each water gets one band a day from a simple rule: **water = the day's air high minus 2 bands, kept between the 30s and the 70s**. Spring-fed water ignores the rule and stays in the 40s to 50s all year. That makes a summer heat wave push a freestone river into the 70s (trout shut down) while a spring creek stays in the 50s, which is a good reason to travel.

| Water band | What trout do |
| --- | --- |
| 30s | Barely feed, deep resting lies |
| 40s | Slow; feed on midges and nymphs in the warmest slot |
| 50s and 60s | Prime: feeding hard, hatches thickest |
| 70s | Stressed: feed only at dawn and dusk; a released fish may not survive |

## Weather

Each day rolls one of five weathers from its season's odds. Weather adjusts the temperature band and turns some hatches and fish on or off.

| Weather | Spring | Summer | Fall | Winter | Temperature | Hatches | Fish |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sunny | 35% | 65% | 40% | 30% | No change | Normal | Warier; browns stay under cover until Dusk |
| Overcast | 30% | 15% | 35% | 35% | High minus 1 band | Turns on BWO, march brown and mahogany | Less wary; browns hunt all day. The best fishing weather |
| Rain | 25% | 5% | 20% | 5% | High minus 1 band | Light hatches keep going | Rain hides the line, so less wary; heavy rain colours the water the next day |
| Snow | 5% | 0% | 5% | 30% | High stays in the 30s | Midges only | Slow; feed only in the warmest slot |
| Storm | 5% | 15% | 0% | 0% | High minus 1 band | None | A feeding burst in the slot before it hits, then shut down; lightning sends the player off the water |

Summer storms are the high desert's dry afternoon thunderstorms, so they could be limited to the Afternoon and Dusk slots.

## Hatch calendar

Sixteen real hatches, converted to season days and time slots, in the order they start. The id is what a hatch, a fly and a fish's diet would share.

| Insect id | Name | Season days | Slots | Hook size | Stages fish eat |
| --- | --- | --- | --- | --- | --- |
| `midge` | Midges | Every day; heaviest Fall 21 to Spring 10 | Noon | 18 to 26 | Larva, pupa, adult |
| `baetis` | Blue-winged olive | Winter 21 to Spring 30; Fall 1 to 30 | Afternoon, when overcast | 16 to 22 | Nymph, emerger, dun |
| `skwala` | Skwala stonefly | Spring 1 to 20 | Afternoon | 8 to 12 | Nymph, adult |
| `march_brown` | March brown | Spring 11 to 30 | Morning to Afternoon, when overcast | 12 to 14 | Nymph, dun |
| `caddis` | Caddis | Spring 15 to Fall 20 | Afternoon, Dusk | 14 to 16 | Larva, pupa, adult |
| `pmd` | Pale morning dun | Spring 15 to Summer 30 | Morning | 16 to 18 | Nymph, emerger, dun |
| `green_drake` | Green drake | Spring 25 to Summer 10; Fall 11 to 20 | Afternoon | 10 to 12 | Nymph, dun |
| `salmonfly` | Salmonfly | Spring 25 to Summer 10 | Noon | 4 to 8 | Nymph, adult |
| `golden_stone` | Golden stone | Summer 1 to 10 | Noon | 6 to 10 | Nymph, adult |
| `callibaetis` | Speckled dun (lakes) | Summer 1 to Fall 10 | Morning | 14 to 16 | Nymph, dun, spinner |
| `damselfly` | Damselfly (lakes) | Summer 1 to 30 | Noon | 10 to 12 | Nymph, adult |
| `yellow_sally` | Little yellow stone | Summer 1 to 20 | Afternoon | 14 to 16 | Adult |
| `trico` | Trico | Summer 8 to Fall 5 | Dawn | 20 to 24 | Spinner |
| `terrestrial` | Hoppers, ants, beetles | Summer 11 to Fall 10 | Noon, Afternoon | 8 to 16 | Adult |
| `mahogany` | Mahogany dun | Fall 1 to 20 | Afternoon, when overcast | 14 to 16 | Nymph, dun |
| `october_caddis` | October caddis | Fall 11 to 20 | Afternoon | 8 to 10 | Pupa, adult |

Streamers imitate prey that never hatches: `sculpin`, `baitfish`, `crayfish`, `leech`, `egg`, plus `plankton` and `frog` for lake fish.

## The 18 species

Ordered roughly by when a player might meet them. Sizes are typical, with the trophy end in brackets. `redband` and `brook` already exist in the game.

| Id | Species | Origin | Habitat | Style | Size, in | Season days | Rarity |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `redband` | Redband rainbow | Native | Seams, runs, riffles | Dry, nymph | 8 to 16 (22) | All year | Common |
| `brook` | Brook trout | Introduced | Small creeks, pockets, high lakes | Dry, nymph | 6 to 12 (18) | Spring 11 to Fall 30 | Common |
| `whitefish` | Mountain whitefish | Native | Deep runs, in schools | Nymph | 10 to 16 (20) | All year, best in Winter | Common |
| `largescale_sucker` | Largescale sucker | Native | Pool bottoms, slow runs | Nymph (bycatch) | 14 to 22 (26) | All year | Common |
| `stocked_rainbow` | Hatchery rainbow | Stocked | Pools, lakes | Dry, nymph | 10 to 14 (20) | Spring 11 to Fall 30 | Common |
| `brown` | Brown trout | Introduced | Undercut banks, deep pools | Streamer, dry at dusk | 12 to 20 (30) | All year, best Fall 1 to 30 | Uncommon |
| `kokanee` | Kokanee | Native | Open lake, deep | Small streamer | 9 to 14 (20) | Spring 21 to Fall 10 | Uncommon |
| `smallmouth` | Smallmouth bass | Introduced | Rocky lake shelves | Streamer, popper | 10 to 15 (20) | Summer 1 to 30 | Common in summer |
| `largemouth` | Largemouth bass | Introduced | Weedy shallows | Streamer, popper | 12 to 18 (22) | Summer 1 to 30 | Uncommon |
| `pikeminnow` | Northern pikeminnow | Native | Slow runs, eddies | Streamer (bycatch) | 10 to 18 (24) | Spring 21 to Fall 20 | Common |
| `bull_trout` | Bull trout | Native, threatened | Deep cold pools, lakes | Streamer | 18 to 26 (36) | All year, best Fall 1 to 30 | Rare |
| `lake_trout` | Lake trout | Introduced | Deep lakes | Deep streamer | 20 to 30 (40) | Shallow Spring 21 to Summer 10, deep after | Rare |
| `pink_salmon` | Pink salmon | Native, sea-run | Runs and tailouts, in big schools | Swung or stripped pink fly | 18 to 24 (26) | Summer 21 to Fall 10, odd-numbered years only | Common in a run year |
| `coho` | Coho salmon | Native, sea-run | Slow pools, logjam edges | Stripped streamer | 24 to 30 (34) | Fall 1 to 30 | Uncommon |
| `summer_steelhead` | Summer steelhead | Native, sea-run | Tailouts, walking-speed runs | Swung fly, skated dry | 22 to 30 (34) | Summer 11 to Fall 30, best Fall 1 to 10 | Rare |
| `winter_steelhead` | Winter steelhead | Native, sea-run | Deep runs, tailouts | Deep swung streamer | 24 to 32 (38) | Winter 1 to Spring 20 | Rare |
| `sockeye` | Sockeye salmon | Native, sea-run | Shallow lanes along the bank | Small bright fly | 20 to 26 (28) | Summer 1 to 20 | Rare |
| `chinook` | Chinook salmon | Native, sea-run | Deep resting pools | Swung streamer | 28 to 36 (48) | Spring run Spring 11 to Summer 10; fall run Fall 1 to 20 | Legendary |

The existing `cutthroat` can stay as is, since your rivers don't need to follow real ranges.

## Species traits

Starting numbers for the fish logic. Surface, selectivity and wariness run 0 to 1. Set window, pull and toughness use the same scale as today's fish files.

| Id | Best lies | Prime water | Best slots | Eats most | Surface | Selective | Wary | Set window, s | Pull / tough | Fight |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `redband` | Seam, run, pocket | 50s to 60s | Morning to Dusk | Caddis, mayflies, stoneflies | 0.7 | 0.5 | 0.5 | 0.1 to 1.0 | 0.75 / 1.2 | Runs and jumps |
| `brook` | Pocket, undercut, pool | 40s to 50s | Any daylight | Anything | 0.8 | 0.2 | 0.4 | 0.08 to 0.45 | 0.55 / 0.8 | Short and scrappy |
| `whitefish` | Deep run, pool | 40s to 50s | Noon | Midges, caddis larvae | 0.3 | 0.3 | 0.3 | 0.05 to 0.3 | 0.45 / 0.7 | Twisting |
| `largescale_sucker` | Pool bottom, slow run | 40s to 60s | Any | Algae, midge larvae | 0 | 0.1 | 0.3 | 0.05 to 0.3 | 0.6 / 1.0 | Dogged, no jumps |
| `stocked_rainbow` | Pool, run | 50s to 60s | Any daylight | Midges, mayflies | 0.6 | 0.2 | 0.2 | 0.15 to 0.7 | 0.5 / 0.7 | Weak |
| `brown` | Undercut, deep pool | 50s to 60s | Dusk, Night, Dawn | Sculpin, baitfish, crayfish | 0.4 | 0.7 | 0.9 | 0.2 to 0.7 | 0.85 / 1.4 | Dives for cover |
| `kokanee` | Open lake, 3 to 15 m | 50s | Dawn, Dusk | Plankton, midges | 0.1 | 0.3 | 0.4 | 0.1 to 0.5 | 0.6 / 0.8 | Soft mouth, head shakes |
| `smallmouth` | Rocky shelf | 60s to 70s | Morning, Afternoon | Crayfish, baitfish | 0.6 | 0.1 | 0.3 | 0.15 to 0.7 | 0.8 / 1.1 | Jumps |
| `largemouth` | Weed beds | 70s | Dawn, Dusk | Baitfish, frogs | 0.7 | 0.1 | 0.4 | 0.2 to 0.8 | 0.85 / 1.2 | Bulldog, then jumps |
| `pikeminnow` | Slow run, eddy | 50s to 70s | Any | Baitfish | 0.3 | 0.1 | 0.2 | 0.15 to 0.7 | 0.5 / 0.6 | One run, then quits |
| `bull_trout` | Deep pool, lake deep | 40s | Dawn, Dusk | Fish, sculpin | 0.1 | 0.3 | 0.6 | 0.2 to 0.8 | 1.0 / 1.6 | Heavy and deep |
| `lake_trout` | Lake deep, 10 to 30 m | 40s to 50s | Dawn | Kokanee | 0 | 0.2 | 0.5 | 0.2 to 0.8 | 0.9 / 1.8 | Heavy and deep |
| `pink_salmon` | Run, tailout, in schools | 50s | Any daylight | Strikes pink flies | 0.1 | 0.1 | 0.3 | 0.15 to 0.6 | 0.8 / 1.0 | Short, strong runs |
| `coho` | Slow pool, logjam edge | 40s to 50s | Dawn, Dusk, after rain | Strikes baitfish flies | 0.2 | 0.1 | 0.5 | 0.2 to 0.8 | 1.2 / 1.8 | Jumps and cartwheels |
| `summer_steelhead` | Tailout, run | 50s to 60s | Dawn, Dusk | Barely eats | 0.3 | 0.1 | 0.5 | 0.4 to 1.2 | 1.3 / 2.0 | Long runs and jumps |
| `winter_steelhead` | Deep run, tailout | 40s | Noon | Eggs, barely eats | 0.1 | 0.1 | 0.5 | 0.4 to 1.2 | 1.4 / 2.2 | Heavy, long runs |
| `sockeye` | Shallow bank lane | 50s | Dawn | Barely eats | 0 | 0.2 | 0.6 | 0.2 to 0.7 | 1.1 / 1.6 | Fast runs and jumps |
| `chinook` | Deep resting pool | 40s to 50s | Dawn | Doesn't eat | 0 | 0.1 | 0.6 | 0.3 to 1.0 | 1.5 / 2.5 | Heavy runs |

A few behaviours the table can't hold: brook trout overpopulate and stay small, so they scatter rather than taking the best lies. Whitefish hold in schools. Steelhead and salmon take out of aggression, not hunger, so their mood comes from temperature and light instead of the hatch. Bull trout are catch-and-release only, which is a natural place to teach why.

## Open questions

- [ ] Which species go in the first slice? Suggested: redband, brook and whitefish, with brown as the first trophy.
- [ ] Keep bass and pikeminnow, or limit the list to trout, char and salmon?
- [ ] Should fish read the water band from the simple air-minus-2 rule, or should each river get its own water band per season that you set by hand?

These fields get added to the game one at a time, each with its own REQ, as the system that reads it is built: lies with fish placement, temperature and light with mood, and diet and selectivity with hatches. Lake lies will need still-water support, since the river doesn't produce them yet.

## Sources

- Hatch months and sizes: Fly Fishing Place hatch charts for the [Deschutes](https://theflyfishingplace.com/pages/deschutes-river-oregon-hatch-chart), [Metolius](https://theflyfishingplace.com/pages/metolius-river-oregon-hatch-chart) and [Crooked](https://theflyfishingplace.com/pages/crooked-river-oregon-hatch-chart)
- Temperature bands, lies and fight numbers are general trout biology turned into game tuning, not sourced figures.
