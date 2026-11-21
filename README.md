# Holy Math

The maths behind a healing priest in **World of Warcraft: Forever**, worked out on your own live stats and the game's own spell data.

![Holy Math options window](media/screenshot.webp)

## What it does

- **Item tooltips:** how much an item gains or loses you in healing per second, e.g. `Holy Math: +16.2 HPS (+1.8%)`. The whole model is rerun with the item swapped in, not a fixed stat weight. Gear a priest can't use says so ("can't wear Plate", "for Mage only").
- **Your HPS and stat values:** what you heal per second over a fight, and what each stat is worth to you in healing power right now: intellect, MP5 and spirit per point, crit and haste per 1% (the way gear gives them).
- **Playstyles:** Renew filler, Greater Heal filler, Flash Heal filler, Prayer of Healing filler, PW:Shield on tank, and Renewed Hope tank (Discipline, with the talent). Each picks the spell ranks that heal the most for you.
- **Spell overview:** every healing spell you know: heal, mana, healing per mana and per second, and its most mana-efficient rank. Click any spell to unfold all its ranks, with how much of your healing power each low rank still gets.
- **Math tab:** a sheet of how every number is worked out, with your own numbers in it: your stats and talents, every spell the fight casts step by step (click a rank on Your spells to add any other), the fight's mana and casts, each stat value, and your overheal per spell. Every line says where its number comes from: the game, the game data, measured in game, your setting, or an assumption of the model.
- **Type your own numbers:** click any boxed value on the Math tab (healing power, crit, a crit's size, regen, a talent's value, overheal, ...) and type over it. A spell rank's own data (base heal, coefficient, cost) is the game's, checked against its tooltips, so it isn't typed over. Your value is then used everywhere (HPS, stat values, Your spells, item tooltips) and shows in blue, with an arrow that puts the game's back. A line at the bottom of the window says how many are yours; right-click one, or **Put all back**, or `/hm reset`, to use the game's again.
- **Checks itself against the game:** every spell rank you know is compared with the game's own spell tooltip. `/hm check` shows the comparison; the window only speaks up when something doesn't match.

Everything recalculates by itself when your gear, buffs, talents or settings change.

## Install

Copy the `HolyMath` folder into `World of Warcraft/_forever_/Interface/AddOns/` and restart the game. Holy Math stays off on other classes.

## Use

| Command | |
|---|---|
| `/hm` | open or close the window |
| `/hm show` | the summary in chat |
| `/hm check` | where every number comes from, and how the model compares with the game |
| `/hm dump` | save everything Holy Math reads (for bug reports), then `/reload` |
| `/hm set fight <seconds>` | fight length, and other settings (`/hm set` lists them) |
| `/hm reset` | put back every value you typed on the Math tab |

The **Settings** tab holds the fight: its length (default 120 s, a typical raid boss), playstyle, Prayer of Mending bounces, Mana Tide, mana potions and Inspiration, next to the result. The overheal you expect per spell is set on the **Math** tab (Settings has a button to it). Every setting explains itself on hover. The **Tooltips** tab controls what item tooltips show.

## Where the numbers come from

- **Your stats** (healing power, crit, mana, regen, talents, known ranks) are read from the game.
- **Spell and talent data** (base heals per rank and level, coefficients, costs, talent values, spirit regen) is the game's own data as extracted by [wowsims/forever](https://github.com/wowsims/forever). `Models/PriestData.lua` is generated from it by `tools/gen_priest_data.py`.
- **The fight model** (mana budget, cooldowns, regen pauses, Inner Focus, Inspiration) started as a port of [doublezug's healer-priest spreadsheet](https://docs.google.com/spreadsheets/d/19SaCaDQJzhMFL-nIW4ryzFwI53FmsnDvaxRfLbvM-CE/edit?gid=1807392634#gid=1807392634). Its formulas are reproduced exactly in the tests, and the places where the game shows something different are corrected and documented in the code.
- **Checked in game:** costs (with talents such as Improved Healing), base heals, coefficients, downranking (the penalty starts 12 levels after a rank's max level), Holy and Discipline talent values, intellect to crit (the game data's level-60 value, and measured at 49 and 50), and the regen formula all match the client's own numbers. Prayer of Mending ignores the healing power Spiritual Guidance gives you from spirit, as the client's tooltip shows.
- **Downranking and tooltips:** from level 50 the game's spell tooltips show low ranks at full healing power, but their real heals still have the penalty (Renew rank 1 ticks for exactly the penalised amount). Holy Math uses what the spells really heal.

## Development

The model runs outside the game too:

```bash
lua5.1 tests/run_tests.lua    # the model: the sheet reproduced, and the client's own tooltip numbers
lua5.1 tests/smoke_wow.lua    # the whole addon against a fake game client
```

After a game patch, regenerate the spell data from a fresh wowsims checkout:

```bash
git clone --depth 1 https://github.com/wowsims/forever /tmp/wowsims-forever
python3 -I tools/gen_priest_data.py /tmp/wowsims-forever > Models/PriestData.lua
```

## Credits

- Spell data: [wowsims](https://github.com/wowsims/forever), MIT licence (notice in `Models/PriestData.lua`).
- The original healing model: [the healer-priest spreadsheet for WoW: Forever](https://docs.google.com/spreadsheets/d/19SaCaDQJzhMFL-nIW4ryzFwI53FmsnDvaxRfLbvM-CE/edit?gid=1807392634#gid=1807392634) by **doublezug**. Its formulas, playstyles and in-game measurements (downranking, coefficients) are what Holy Math was built from.
