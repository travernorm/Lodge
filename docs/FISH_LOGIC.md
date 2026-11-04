# Fish logic

**Status: draft for Traver's review.** This is the design for how fish appear, how keen they are, and whether they take your fly. It came out of a brainstorm with Traver on 2026-11-02. The code layout (which classes hold what) is in [ARCHITECTURE.md](ARCHITECTURE.md) section 3.5. Building any of it still goes through a REQ per [DEVELOPMENT_PROCESS.md](DEVELOPMENT_PROCESS.md).

## The short version

Fish logic runs in three steps, from slowest to fastest:

```
 CONDITIONS (season, time of day, weather)
     │
     ├──▶ hatch: which bugs, which stage, how thick
     └──▶ water: temperature, level
              │
 1. GENERATION   who lives in this stretch, and where     changes per season / visit
 2. MOOD         how keen each fish is right now          changes per game hour
 3. TAKE         does it eat this presentation            one roll per drift past the fish
```

* **Generation** answers "what's in the river". It uses the stretch (its water types and features), the season and the species table.
* **Mood** answers "are they feeding". It uses the conditions, mostly through the hatch.
* **Take** answers "did I fool it". It uses only the local things: whether the fly came through the fish's lane, and the landing, the drift and the fly.

Time of day, season and weather are **not** variables on each fish. They build one shared **conditions** snapshot for the stretch. That snapshot produces the hatch and the water temperature. Fish then read the hatch and the water, the same way the player reads them.

## Step 1: Generation

### What it decides

Which species are in a stretch, how many fish, how big, and which lie each one holds.

### Inputs

| Input | Where it comes from | What it does |
|---|---|---|
| Lies and their scores | The stretch's baked `RiverField` (river thread) | Where a fish could hold. Each good lie holds one fish, so the river decides the head count. |
| Water type at each lie | The river field: riffle, run, pool, pocket water, seam, tailout, eddy, undercut bank | Which species fit there. Brook trout like small pockets, browns like undercut banks and deep pools, redbands like seams and riffle heads. |
| Features near the lie | Rocks, logs, overhanging cover, depth | Lifts a lie's score for species that like cover. |
| Season and water level | Conditions | Spring runoff pushes fish to the edges; late summer low water packs them into pools. Some species only show up in some seasons (salmon runs, spawning browns in fall). |
| Water temperature | Conditions | A species stays away from water outside its temperature range. |
| Species table | The stretch's data: which species can live here, and how common each is | The base mix. |

### How it works

1. **Count:** take every lie whose score is above a threshold. That's the stretch's capacity. Fill a share of it based on season and how rich the stretch is.
2. **Species:** for each filled lie, pick a species, weighted by how common it is here × how well it fits that water type × whether the temperature suits it.
3. **Size:** roll sizes, then hand the biggest fish to the best lies, with a little noise. Real trout sort themselves this way, since the biggest fish takes the best spot. It also teaches the player that "the best water holds the best fish".
4. **Two lies per fish:** a **resting lie** (deep, slow, covered) and a **feeding lie** (a nearby seam or tailout where food comes by). Mood decides which one it's in. This needs the river field to score lies for resting and feeding separately (to agree with the river thread).
5. **Trophy fish:** a few named fish are placed by hand in the stretch data, each with a home lie. "The big brown under the cabin boulder" is always there, and hard to catch.

### Persistence

The population is generated once per season, or on the first visit, and then **kept**. It isn't rerolled every time you walk on screen.

* A fish you spooked stays wary for a while.
* A fish you caught and released goes back to its lie, wary, and comes back to normal over a few days.
* A fish you kept (to sell at the market) is gone, and the stretch refills slowly. This ties fishing to the economy: overfishing one spot to sell fish makes it worse.
* A little daily churn: some fish swap lies, so a stretch never feels solved.

*Today:* there is no population to keep yet, only the play session. A fish you land is out of the water for the rest of the session (`Fish.State.CAUGHT`), so you can't catch the same trout twice. A fish that breaks off or throws the hook comes back to its lie a few seconds later.

## Step 2: Mood

### What it decides

How keen each fish is to feed, from 0 (shut down) to 1 (feeding hard), and **where it's looking**: up at the surface, or down at nymphs.

### Inputs

| Input | What it does |
|---|---|
| **Hatch** (from conditions) | The biggest driver. Food on the water switches fish on. A heavy hatch means high mood and fish in their feeding lies. The hatch's stage (nymphs, emergers, adults) sets where they're looking, which is what makes dry fly, nymph and streamer each the right answer at different times. |
| **Species response to conditions** | Each species has a temperature range it likes, a light preference (browns like dusk and cloud, brookies don't mind sun) and seasonal activity. |
| **Personal state** | Hunger goes up over time since it last ate. Wariness goes up when it's spooked, hooked or keeps refusing flies, then fades. |
| A little random drift | So two fish in the same conditions aren't identical. |

### Selectivity

A fish feeding hard on a hatch is **easy but picky**: high mood, and the fly match counts for a lot. On a dead afternoon a fish is **sluggish but less fussy**: low mood, but a rough match will do. This one rule gives "match the hatch" its meaning without extra systems.

### When it updates

When the conditions change (about once per game hour) and after events (spooked, hooked, refused). Never per frame.

## Step 3: Take

### When the roll happens

Once per **presentation**: each time the fly drifts through a fish's window. Not once per cast and not every frame. Fish further down the drift each get their own roll as the fly reaches them.

### The roll

```
take chance = mood × lane × landing × drift × fly match
              (clamped to a floor and a ceiling, unless the fish is spooked)
```

| Factor | Meaning | Comes from |
|---|---|---|
| **Mood** | How keen the fish is right now | Step 2 |
| **Lane** | Did the fly come through where the fish is looking? Distance from its feeding line, and depth for nymphs | `FlyState.pos`, `FlyState.depth`, the fish's lie |
| **Landing** | Delicate, fair or splashy | The cast's presentation |
| **Drift** | How drag-free it was | `FlyState.drag` |
| **Fly match** | How much the fly looks like what it's eating, weighted by how selective the fish is | The fly's pattern and the hatch |

### Worked example

A June evening on the test stream. There's a caddis hatch coming off, and a hungry redband is in its feeding lie on the seam below the boulder.

* **Mood 0.8.** Good hatch, dusk light, it hasn't eaten in a while.
* **Lane 1.0.** The fly drifts right down its feeding line.
* **Landing 1.0.** A delicate cast.
* **Drift 0.7.** A little drag building at the end.
* **Fly match 0.9.** An Elk Hair Caddis during a caddis hatch.

Take chance: 0.8 × 1.0 × 1.0 × 0.7 × 0.9 = **about 50%**.

* Same drift with a Royal Wulff (match 0.4): about **22%**.
* Mend earlier so the drift is clean (1.0) with the Caddis: about **72%**.
* Slap it down right on top of the fish: a **spook check** happens instead of a take roll.

### Outcomes and feedback

The roll has four possible results. Each one shows something the player can learn from.

| Result | When | What the player sees |
|---|---|---|
| **Take** | The roll succeeds | A rise and a take, then the hook-set window opens |
| **Refusal** | The roll fails but the chance was decent | The fish comes up, looks and turns away. It means "close, change something": usually the fly or the drag |
| **Ignore** | The roll fails and the chance was low | Nothing. The fly drifts on |
| **Spook** | A splashy landing on top of it, or the line landing over it | A bolt or a wake. The fish goes down or leaves, and its wariness goes up |

### Keeping randomness fair

* **Floor and ceiling.** Even a perfect presentation isn't a sure thing (a ceiling of about 90%). A decent one is never truly impossible (a floor of a few percent), unless the fish is spooked.
* **Streak protection.** After several good presentations in a row with no take, the odds go up a little until something takes. This is the "pity timer" many games use, so bad luck doesn't feel like a broken game.
* **Show the factors while learning.** For example: "Mood 0.8 × Lane 1.0 × Delicate 1.0 × Drag 0.7 × Caddis 0.9 = 50%". Later they can be hidden behind skill, or shown through a perception check.

### Where the dice are

In the fish logic, randomness lives in three places only:

1. Generation: species, sizes, which lies are filled.
2. Mood's small drift.
3. The take roll (and the spook check).

Everything else is deterministic, so the player can learn it. Every roll uses a seeded random number generator, so tests can replay exactly.

## The player can see every variable

If the fish use something the player can't read, the rules feel hidden and broken, which is what happened in the first playtest. So each input has a tell:

| Variable | How the player reads it |
|---|---|
| Lies | Rises and dimples, the read-the-water view, and seams and depth in the art |
| Water type and features | Drawn in the river: riffles, foam lines, boulders, undercut banks |
| Season | The landscape changes (Stardew-style), plus the calendar |
| Time of day and weather | The sky and the light |
| Water temperature and level | A thermometer item, and visible levels on the bank |
| Hatch | Bugs on the water and in the air. A perception check names them and their stage |
| Mood | How often fish are rising. A perception check: "Fish are feeding hard on caddis" |
| Drift and drag | The fly's wake and the line's belly, as now |
| Fly match | The perception check on the hatch, the journal, books, NPC tips |

## Building it up, simplest first

Each layer is tried as a bite rules variant, with its factors on screen. Traver plays each one before the next goes on, and the winner stays. After steps 1, 2 and 4 Traver picked Drift past with the fly match (2026-11-02), so today `DriftPastRules` is the only bite rules and the others are gone. A new layer brings back a second variant to compare against it.

1. **Landing roll:** distance to the fish × landing, rolled once when the fly lands. Mood, drift and fly match are fixed at 1. (Built, then dropped 2026-11-02 when Traver picked Drift past.)
2. **Drift:** the "Drift past" bite rules, built 2026-11-02 at Traver's call and now the only bite rules. Each fish rolls once per pass, as the fly drifts within 1 m of it (landing on top of it counts as a pass). The chance is the species' `bite_chance` split into three equal shares added together: in lane, a delicate landing within 3 m (a fair one gets half; a splashy one isn't punished), and a drift with no drag. Drag is measured as the fly's slip against the water under it at the pass's worst moment (`DriftModel.slip`), so drag, skating and an early mend's jolt all count. These are bonuses added together rather than the multiplied factors above. The full formula can replace them once mood and fly match arrive.
3. **Refusals and streak protection:** add the four outcomes and the pity timer.
4. **Fly match:** built 2026-11-02 (REQ-0003) as the "Match the fly" bite rules, then folded into Drift past when the other rules were dropped. Drift past × fly match, where fly match = 1 − selectivity × (1 − appetite), and appetite is the fish's highest `diet` weight among the bugs the fly imitates. Diets are fixed per species for now.
5. **One hatch:** a fixed caddis hatch that raises the diet weight of what's coming off, and selectivity when it's thick.
6. **Mood from time of day:** the hatch comes and goes over a day, and mood follows it.
7. **Generation from lies:** several fish placed from the river field's lie scores, biggest in the best lies. Built 2026-11-04 (REQ-0007) as `FishGenerator`, with the season window, water temperature and abundance from step 8, and the hatch lifting how often fish rise. Resting lies (deep, slow, covered water, with a dry fly discount) and fish spread along the whole river came in REQ-0011. Water types came with REQ-0010: each lie picks a species weighted by how much it likes that water (`FishSpecies.habitat`). Moving between resting and feeding lies with mood, and persistence, are still to come.
8. **Seasons and weather:** the full conditions snapshot.

Steps 1 to 3 need nothing new from other systems. Step 4 is built. Step 7 needs the river thread's lie work (PR #7, then resting and feeding scores). Step 8 needs the `Clock`.

## Data this implies

These are proposals; each field change to a data class needs its own REQ.

* **`FishSpecies`:** habitat preference per water type, temperature range, light preference, diet (`DietEntry`: insect and weight), selectivity, seasonal activity and presence, size range (already there), fight stats (already there).
* **`Fish`** (runtime): species, length, resting lie, feeding lie, mood, hunger, wariness, refusal count, presentations since last take.
* **`Stretch`:** the baked river field(s), the species table with abundance, trophy fish placements, how fast it refills.
* **`Hatch`:** insect id, stages, time window, intensity by weather.
* **`Season`:** its hatch table, water temperature and level ranges.
* **`FlyPattern`:** what it imitates (insect id and stage), size, style (dry, emerger, nymph, streamer).
* **`Conditions`** (runtime value): season, time of day, weather, water temperature, water level, the active hatch and its stage.

## Open questions

1. Should keeping fish to sell deplete a stretch? (Recommended: yes, slowly. It links fishing to the market.)
2. Roughly how many fish should one screen hold: 1 to 3, or 5 to 10?
3. Should odds stay on screen for good, or fade out as the player's skill or journal grows?
4. Is "the biggest fish takes the best lie" right for every species, or should some (like brookies) be scattered?
