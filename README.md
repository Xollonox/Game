# Game

A physics-driven melee combat game in the spirit of [Half Sword](https://store.steampowered.com/app/2397300/Half_Sword/),
built with Godot 4.7 and Jolt physics. Characters are **active ragdolls**: the
body is a real physics rig that chases an animated pose, so a solid hit
overpowers it and the character staggers, goes down, and picks itself back up —
no canned knockdown animations.

## Play in the browser

Once GitHub Pages is enabled (see below), the build in [`docs/`](docs/) is
playable at:

**https://xollonox.github.io/Game/**

### Controls

| Input | Action |
|---|---|
| `W` `A` `S` `D`, or the on-screen joystick | Walk (camera-relative) |
| `Space` / left click, or the on-screen SWING button | Sword swing — a real physics-driven blade, not a hitscan; it deals damage from its own measured contact speed |
| `1` / `2` / `3` | Hit yourself: light / heavy (stagger) / crushing (ragdoll) |
| Right-drag, `Q` / `E`, or a touch drag on the right side of the screen | Orbit the camera |

On a touchscreen, a virtual joystick (bottom-left) and swing button (bottom-right)
appear automatically — see `scripts/touch_controls.gd`.

## Running from source

Install Godot 4.7+ (`./install-godot.sh`, or see [INSTALLATION.md](INSTALLATION.md)), then:

```bash
godot project.godot      # open in the editor
godot --headless --path . # run headless
```

## Re-exporting the web build

The playable build in `docs/` is committed so GitHub Pages needs no toolchain in
CI. After changing the game, re-export and commit it:

```bash
godot --headless --import
godot --headless --export-release "Web" docs/index.html
```

Thread support is deliberately **off** in the export preset: Godot's threaded
web build needs `SharedArrayBuffer`, which requires `Cross-Origin-Opener-Policy`
and `Cross-Origin-Embedder-Policy` response headers — and GitHub Pages cannot
set custom headers. The single-threaded build runs there without them.

## Enabling GitHub Pages (one-time)

Repository **Settings → Pages**, then either:

- **Source: GitHub Actions** — `.github/workflows/pages.yml` publishes `docs/` on
  every push to `main`, or
- **Source: Deploy from a branch** → branch `main`, folder `/docs`.

## Project layout

| Path | What's in it |
|---|---|
| `scenes/` | `arena.tscn` (the playable scene), `player.tscn`, `dummy.tscn` |
| `scripts/` | `kickback_actor.gd` (shared ragdoll actor), `player.gd`, `physics_sword.gd` (the weapon), `arena.gd`, `combat_profiles.gd`, `touch_controls.gd` |
| `addons/kickback/` | Active-ragdoll plugin (MIT) — see `assets/CREDITS.md` |
| `assets/` | Models, animations and SFX, all CC0 — provenance in `assets/CREDITS.md` |
| `docs/` | Exported web build served by GitHub Pages |
| `research.md` | How Half Sword's combat works and how to reproduce it |
| `PLAN.md` | Phased build plan and current status |

## Licensing

Project code is unlicensed so far (TBD). Every third-party asset and addon is
CC0 or MIT, tracked with its source in [`assets/CREDITS.md`](assets/CREDITS.md).
