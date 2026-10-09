# Bot Brigade

A World of Warcraft add-on for playing with bots on a private **AzerothCore + Playerbots** server (WotLK 3.3.5a).

Call your other characters into your group, pick what the team should do, and play. Bot Brigade takes care of the rest.

## Download and install

1. Go to the [latest release](../../releases/latest) and download **BotBrigade.zip**.
2. Unzip it. You get a folder called **BotBrigade**.
3. Move the **BotBrigade** folder into your game's `Interface/AddOns` folder.
   It should end up as `Interface/AddOns/BotBrigade/BotBrigade.toc`.

Then start the game. At the character screen, click **AddOns** and make sure **Bot Brigade** is ticked.

If the game was already running, close it fully and start it again. New add-ons are only found when the game starts.

## How to use it

A round medallion appears on your screen with your banner in the middle.

- **Your team** sits around the banner, with health bars and names.
- **Click the banner** to open the medallion and choose what to do:

| | Button | What it does |
|---|---|---|
| In the world | **Call Team** | Brings your other characters into your group, next to you. Right-click it to choose who comes. |
| | **Follow Me** | Your team follows you and fights with you. Use this for questing. |
| | **Wait Here** | Your team stops and waits. |
| In a dungeon | **Careful** | The tank leads and pulls every group of enemies back to the team. Slowest, safest. |
| | **Smart** | The tank leads, charges small groups and pulls big ones back. Recommended. |
| | **Leeroy** | The tank leads and charges into everything. Fastest, riskiest. |

You can also press **1** to **6** while the medallion is open. **Escape** closes it.

**Click a teammate's picture** to bring them to you, change their role (Tank, Healer, Damage), train them, or log them out.

**Right-click the banner** for options: size, sounds, lock position, and the automatic helpers below.

**Drag** the medallion from anywhere on it to move it.

## Things it does for you automatically

- **Shares your quests.** Every quest you accept is shared with your team. When you turn it in, teammates who have it finish it too and get the experience.
- **Keeps the team together.** If a teammate falls far behind, gets stuck, or is left behind after a flight path or hearthstone, they're brought back to you.
- **Revive button.** When a teammate dies, a glowing **Revive** button appears on the medallion. During a fight it waits until the fight ends.
- **New skills on level-up.** When a teammate levels up, they learn their new abilities.
- **Loot rules.** While questing, loot is set to Free for All so quest items and drops all go to you (your team still finishes shared quests when you turn them in). In dungeons it switches to Need Before Greed so your team can roll on gear. You must be the group leader.
- **Quieter chat.** Bot chatter shows up in small speech bubbles instead of filling your chat window. You can turn this off in the options.

## Slash commands

| Command | What it does |
|---|---|
| `/bb` | Show or hide Bot Brigade |
| `/bb team` | Call your team |
| `/bb pick` | Choose who's on your team |
| `/bb quest` | Follow Me |
| `/bb stop` | Wait Here |
| `/bb share` | Share all your quests with your team |
| `/bb revive` | Revive fallen teammates |
| `/bb scale 1.2` | Make it bigger or smaller |
| `/bb reset` | Put it back in the default spot |

Key bindings are under **Key Bindings → Bot Brigade** in the game menu.

## What your server needs

- **mod-playerbots**, with players allowed to use their own characters as bots (the default).
- The three dungeon buttons need the separate **mod-dungeon-clear** server module. Without it, Bot Brigade tells you so, and everything else still works.

## For developers

- `BotBrigade/` is the add-on itself (Lua 5.1, Interface 30300).
- `tests/` runs the add-on against a mocked WoW API: `lua5.1 tests/run.lua` from the repository root.
- `tools/make_media.py` repaints the textures in `BotBrigade/Media/` (needs Python with Pillow).
- `tools/package.sh` builds `dist/BotBrigade.zip` for a release.
