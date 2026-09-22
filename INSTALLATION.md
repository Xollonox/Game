# Godot Engine Installation Guide

This is a Godot game project. To develop and run this game, you need to install Godot Engine 4.7+ (latest stable).

## Quick Installation (Recommended)

Run the included installation script to download and install the latest Godot Engine:

```bash
chmod +x install-godot.sh
./install-godot.sh
```

This script will:
- Detect your OS (Linux, macOS, Windows)
- Download the latest stable Godot 4.7+
- Extract it to `~/.godot/`
- Create a symlink at `~/.local/bin/godot`
- Guide you to add it to your PATH if needed

After installation, open the project with:
```bash
godot project.godot
```

## Manual Installation Instructions

### Option 1: Download from Official Website (Recommended)

1. Visit https://godotengine.org/download/windows
2. Download Godot Engine 4.7+ (matches the version in `project.godot`)
3. Extract the archive
4. Add the Godot executable to your PATH, or run it directly

### Option 2: Install via Package Manager

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install godot
```

**macOS with Homebrew:**
```bash
brew install godot
```

**Windows with Chocolatey:**
```bash
choco install godot
```

### Option 3: Build from Source

Clone the Godot repository and build:
```bash
git clone https://github.com/godotengine/godot.git
cd godot
git checkout 4.7-stable
scons
```

## Opening the Project

1. Launch Godot Engine
2. Click "Open Project"
3. Navigate to this repository folder
4. Select `project.godot`
5. Click "Open" to load the project

## Project Structure

```
Game/
├── project.godot          # Godot project configuration
├── scenes/                # Game scenes (.tscn files)
├── scripts/               # GDScript files (.gd files)
├── assets/                # Images, audio, and other resources
│   ├── images/
│   ├── audio/
│   └── fonts/
├── INSTALLATION.md        # This file
└── README.md              # Project documentation
```

## Running the Game

After opening the project in Godot:
- Click the "Play" button (▶) in the top right to run the game
- Or press `F5` to play the current scene
- Or press `F6` to play the main scene

## Next Steps

1. Create your first scene in `scenes/main.tscn`
2. Add game assets to the `assets/` folder
3. Write game logic in GDScript files in the `scripts/` folder
4. Check the [Godot Documentation](https://docs.godotengine.org/) for tutorials and API reference

## Troubleshooting

**Missing icon.svg:**
If you get an error about `icon.svg`, you can disable it in the project settings or provide an SVG icon file.

**Version Mismatch:**
Make sure you're using Godot 4.7 or newer. If you have a different version, you may need to update the `config/features` in `project.godot`.

For more help, visit the [Godot Community](https://godotengine.org/community/)
