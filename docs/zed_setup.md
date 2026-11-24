# Zed Setup

← Back to the [project README](../README.md)

## Configuring the LÖVE Binary Path

Before running the **`Run Game`** task, make sure the `"command"` field in [`.zed/tasks.json`](../.zed/tasks.json) matches where the LÖVE binary is installed on your operating system.

### 1. macOS (default in `.zed/tasks.json`)
```json
{
  "label": "Run Game",
  "command": "/Applications/love.app/Contents/MacOS/love",
  "args": ["."],
  "cwd": "$ZED_WORKTREE_ROOT"
}
```

### 2. Linux
```json
{
  "label": "Run Game",
  "command": "love",
  "args": ["."],
  "cwd": "$ZED_WORKTREE_ROOT"
}
```
*(Or `"/usr/bin/love"` / `"/usr/games/love"`, depending on your distro's package manager.)*

### 3. Windows
```json
{
  "label": "Run Game",
  "command": "C:\\Program Files\\LOVE\\love.exe",
  "args": ["."],
  "cwd": "$ZED_WORKTREE_ROOT"
}
```

## Recommended Zed Keybindings

Add the following to your user keymap (`~/.config/zed/keymap.json`, accessible via `Cmd+K Cmd+S` in Zed) to launch your game with `Cmd+Return`, open the task modal with `Cmd+Shift+R`, and close the task terminal with `Cmd+.`:

```json
[
  {
    "context": "Workspace",
    "bindings": {
      "cmd-shift-r": "task::Spawn",
      "cmd-return": ["task::Spawn", { "task_name": "Run Game" }]
    }
  },
  {
    "context": "Terminal",
    "bindings": {
      "cmd-.": "pane::CloseActiveItem"
    }
  }
]
```

## Why `emmylua` Is Explicitly Disabled in `.zed/settings.json`

If you have both the **Lua** (`lua-language-server`) and **EmmyLua** (`emmylua_ls`) extensions installed in Zed, Zed launches **both** language servers for `.lua` files.

`lua-language-server` reads [`.luarc.json`](../.luarc.json) and loads `${3rd}/love2d/library/`. `emmylua_ls` does not include that third-party library, so it shows false `undefined global variable: love` errors (or aggressively inserts broken `local love = require(...)` lines on autocomplete).

To prevent this, [`.zed/settings.json`](../.zed/settings.json) pins `lua-language-server` and disables `emmylua` for this workspace:

```json
{
  "languages": {
    "Lua": {
      "language_servers": ["lua-language-server", "!emmylua"]
    }
  }
}
```
