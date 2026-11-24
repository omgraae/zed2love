# Building & Zed Tasks

← Back to the [project README](../README.md)

## Building for WebAssembly (WASM) & Zed Tasks

[`Makefile`](../Makefile) provides targets for running, packaging, and compiling your game to WebAssembly using `love.js`. Every target is pre-wired as a Zed task in [`.zed/tasks.json`](../.zed/tasks.json):

| Zed Task Label | CLI Command | Description |
| :--- | :--- | :--- |
| **`Run Game`** | `make run` | Runs the root game locally using your LÖVE binary |
| **`Example 1..6: ...`** | `love examples/<name>` | Runs any of the 6 example games in `examples/` |
| **`Package .love`** | `make love` | Packages the project into `build/zed2love.love` |
| **`Build WASM`** | `make wasm` | Builds the `.love` file and compiles the HTML5/WASM bundle into `build/web/` |
| **`Serve WASM`** | `make serve` | Builds the WASM bundle and serves it at `http://localhost:8000` |
| **`Clean Build`** | `make clean` | Removes the `build/` and `dist/` directories |

You can customize the game name, browser tab title, and WASM memory allocation (in bytes) either in [`Makefile`](../Makefile) or via CLI overrides:

```sh
make wasm GAME_NAME=my_game TITLE="My Awesome Game" MEMORY=134217728
```

## Requirements

`make wasm` needs `make`, `zip`, and Node.js with [`love.js`](https://github.com/Davidobot/love.js) (the `Makefile` falls back to `npx --yes love.js` if it isn't installed globally). `make serve` also needs `python3`. See [Getting Started → Dependencies](./getting_started.md#dependencies).
