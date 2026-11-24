# zed2love Makefile
# Builds .love archives and WebAssembly (WASM) web bundles via love.js
# Includes automatic discovery of Zed's bundled Node.js runtime if node/npx is not on PATH.

GAME_NAME   ?= zed2love
TITLE       ?= zed2love
MEMORY      ?= 67108864
BUILD_DIR   ?= build
WASM_DIR    ?= $(BUILD_DIR)/web
LOVE_FILE   ?= $(BUILD_DIR)/$(GAME_NAME).love
PORT        ?= 8000
EXAMPLES    := train_ride mario_clone solitaire wolfendoom utopia shadermaxxing

# Automatically append Zed's bundled Node.js bin directory to PATH if present
ZED_NODE_MAC   := $(wildcard $(HOME)/Library/Application\ Support/Zed/node/node-*/bin)
ZED_NODE_LINUX := $(wildcard $(HOME)/.local/share/zed/node/node-*/bin)
export PATH    := $(PATH):$(ZED_NODE_MAC):$(ZED_NODE_LINUX):/opt/homebrew/bin:/usr/local/bin

# Love2D binary (override via: make run LOVE=/path/to/love)
ifeq ($(OS),Windows_NT)
	LOVE ?= C:/Program Files/LOVE/love.exe
else ifeq ($(shell uname -s),Darwin)
	LOVE ?= /Applications/love.app/Contents/MacOS/love
else
	LOVE ?= love
endif

# Exclude non-game files when packaging the root .love archive
EXCLUDES := \
	"*.git*" \
	"*.zed*" \
	"*.DS_Store" \
	".luarc.json" \
	"Makefile" \
	"README.md" \
	"LICENSE" \
	"main.lua.example" \
	"examples/*" \
	"skills/*" \
	".agents/*" \
	"$(BUILD_DIR)/*" \
	"dist/*"

.PHONY: all run love wasm wasm-examples wasm-hub serve clean help

all: wasm

## Run the game locally with LÖVE
run:
	"$(LOVE)" .

## Package the project into a .love zip archive
love: $(LOVE_FILE)

$(LOVE_FILE):
	@mkdir -p "$(BUILD_DIR)"
	@rm -f "$(LOVE_FILE)"
	zip -9 -r "$(LOVE_FILE)" . -x $(EXCLUDES)
	@echo "Created $(LOVE_FILE)"

## Build the root project and all 6 example games to WebAssembly (WASM)
wasm: $(LOVE_FILE)
	@mkdir -p "$(WASM_DIR)"
	@if command -v love.js >/dev/null 2>&1; then \
		love.js "$(LOVE_FILE)" "$(WASM_DIR)" -t "$(TITLE)" -m $(MEMORY) -c; \
	elif command -v npx >/dev/null 2>&1; then \
		npx --yes love.js "$(LOVE_FILE)" "$(WASM_DIR)" -t "$(TITLE)" -m $(MEMORY) -c; \
	else \
		echo "Error: 'love.js' (or Node.js 'npx') is required to build for WASM."; \
		echo "Install Node.js and run: npm install -g love.js"; \
		exit 1; \
	fi
	@$(MAKE) wasm-examples
	@$(MAKE) wasm-hub
	@echo "WASM build complete in $(WASM_DIR)"

## Package and build all 6 example games into $(WASM_DIR)/examples/<name>
wasm-examples:
	@mkdir -p "$(BUILD_DIR)/examples" "$(WASM_DIR)/examples"
	@for ex in $(EXAMPLES); do \
		echo "=== Building example to WASM: $$ex ==="; \
		rm -f "$(BUILD_DIR)/examples/$$ex.love"; \
		(cd "examples/$$ex" && zip -9 -q -r "../../$(BUILD_DIR)/examples/$$ex.love" . -x "*.DS_Store"); \
		zip -9 -q -r "$(BUILD_DIR)/examples/$$ex.love" src -x "*.DS_Store"; \
		mkdir -p "$(WASM_DIR)/examples/$$ex"; \
		if command -v love.js >/dev/null 2>&1; then \
			love.js "$(BUILD_DIR)/examples/$$ex.love" "$(WASM_DIR)/examples/$$ex" -t "zed2love - $$ex" -m $(MEMORY) -c; \
		elif command -v npx >/dev/null 2>&1; then \
			npx --yes love.js "$(BUILD_DIR)/examples/$$ex.love" "$(WASM_DIR)/examples/$$ex" -t "zed2love - $$ex" -m $(MEMORY) -c; \
		else \
			echo "Error: 'love.js' or 'npx' not found."; \
			exit 1; \
		fi; \
	done
	@echo "All 6 examples built to $(WASM_DIR)/examples/"

## Generate the dark studio navigation bar and $(WASM_DIR)/examples/index.html showcase hub
wasm-hub:
	@python3 -c 'import pathlib; \
wasm_dir = pathlib.Path("$(WASM_DIR)"); \
items = [ \
  ("Starter Template", "/index.html", wasm_dir / "index.html"), \
  ("1. Train Ride", "/examples/train_ride/index.html", wasm_dir / "examples/train_ride/index.html"), \
  ("2. Mario Clone", "/examples/mario_clone/index.html", wasm_dir / "examples/mario_clone/index.html"), \
  ("3. Solitaire (CRT)", "/examples/solitaire/index.html", wasm_dir / "examples/solitaire/index.html"), \
  ("4. Wolfendoom 3D", "/examples/wolfendoom/index.html", wasm_dir / "examples/wolfendoom/index.html"), \
  ("5. Utopia", "/examples/utopia/index.html", wasm_dir / "examples/utopia/index.html"), \
  ("6. Shadermaxxing", "/examples/shadermaxxing/index.html", wasm_dir / "examples/shadermaxxing/index.html"), \
  ("Examples Hub", "/examples/index.html", None), \
]; \
css_override = "\nbody { background: #0d1017 !important; background-image: none !important; color: #e2e8f0 !important; font-family: system-ui, -apple-system, sans-serif !important; margin: 0; }\nh1 { color: #f8fafc !important; font-size: 1.35rem; margin: 12px 0; }\n.z2l-nav { display: flex; flex-wrap: wrap; gap: 8px; justify-content: center; align-items: center; padding: 10px 16px; background: #161b26; border-bottom: 1px solid #262f42; }\n.z2l-nav a { color: #cbd5e1; background: #1e2636; padding: 6px 12px; border-radius: 6px; font-size: 13px; font-weight: 500; text-decoration: none; border: 1px solid #2e3a52; transition: all 0.15s; }\n.z2l-nav a:hover, .z2l-nav a.active { color: #fff; background: #3b82f6; border-color: #60a5fa; }\n#canvas, #loadingCanvas { border-radius: 8px; box-shadow: 0 12px 36px rgba(0,0,0,0.65); max-width: 96vw; }\nfooter { position: static !important; margin-top: 14px; padding: 10px; text-align: center; color: #94a3b8; }\nfooter button { background: #2563eb; color: #fff; border: none; padding: 6px 12px; border-radius: 5px; cursor: pointer; margin-left: 8px; }\n"; \
[ ( (p.parent / "theme/love.css").write_text((p.parent / "theme/love.css").read_text() + css_override) if (p.parent / "theme/love.css").exists() and "z2l-nav" not in (p.parent / "theme/love.css").read_text() else None, p.write_text(p.read_text().replace("width=\"800\" height=\"600\"", "width=\"1280\" height=\"720\"").replace("<body>", "<body>\n    <nav class=\"z2l-nav\">" + "".join("<a href=\"" + h + "\" class=\"" + ("active" if l==label else "") + "\">" + l + "</a>" for l, h, _ in items) + "</nav>", 1)) if "z2l-nav" not in p.read_text() else None ) for label, href, p in items if p and p.exists() ]; \
cards = [ \
  ("1. Train Ride", "/examples/train_ride/index.html", "Side-scrolling steam train bobbing on tracks with 2 foreground layers, 5 background parallax layers, stationary sunset sky, and an atmospheric depth-haze shader."), \
  ("2. Mario Clone (3 Levels)", "/examples/mario_clone/index.html", "Classic platformer physics across 3 levels (Grassland Stroll, Sky-High Bridges, Sunset Citadel) with question blocks, coins, enemies, moving platforms, and flagpoles."), \
  ("3. Solitaire (CRT Shader)", "/examples/solitaire/index.html", "Klondike Solitaire where every card is a physical spring-damper object with velocity tilt and lift shadows, rendered through a full-screen CRT + scanlines shader."), \
  ("4. Wolfendoom 3D", "/examples/wolfendoom/index.html", "Textured 3D DDA raycaster mapping 64x64 PNG textures onto virtual wall slices with distance fog, plasma rifle animation, and depth-sorted respawning monsters."), \
  ("5. Utopia (Isometric)", "/examples/utopia/index.html", "Peaceful turn-based isometric civilization game on a 24x24 island map focused on cooperative trade routes, shared prosperity, and mutual disaster relief."), \
  ("6. Shadermaxxing (Isometric Maze)", "/examples/shadermaxxing/index.html", "Autogenerated top-down isometric maze with a 3D-shaded rolling ball, 360-degree raytraced 8-segment vision, fog-of-war mist, directional speed blur, impact screen shake, glow, chromasep, and shader hazards."), \
]; \
nav_html = "".join("<a href=\"" + h + "\" class=\"" + ("active" if l=="Examples Hub" else "") + "\">" + l + "</a>" for l, h, _ in items); \
card_html = "".join("<a class=\"card\" href=\"" + h + "\"><h2>" + t + "</h2><p>" + d + "</p><span class=\"btn\">Launch WASM Game &rarr;</span></a>" for t, h, d in cards); \
(wasm_dir / "examples/index.html").write_text("<!doctype html><html><head><meta charset=\"utf-8\"><title>zed2love — WASM Examples Hub</title><style>" + css_override + ".container { max-width: 1100px; margin: 32px auto; padding: 0 20px; } .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 18px; margin-top: 24px; } .card { display: flex; flex-direction: column; justify-content: space-between; background: #161b26; border: 1px solid #283246; border-radius: 10px; padding: 20px; color: #e2e8f0; text-decoration: none; transition: transform 0.15s, border-color 0.15s; } .card:hover { transform: translateY(-3px); border-color: #60a5fa; } .card h2 { margin: 0 0 10px 0; font-size: 1.15rem; color: #fff; } .card p { margin: 0 0 16px 0; font-size: 0.92rem; color: #94a3b8; line-height: 1.45; } .btn { display: inline-block; color: #60a5fa; font-weight: 600; font-size: 0.9rem; }</style></head><body><nav class=\"z2l-nav\">" + nav_html + "</nav><div class=\"container\"><h1>zed2love — WebAssembly (WASM) Examples Showcase</h1><p style=\"color:#94a3b8\">All 6 example games compiled to WebAssembly with <code>love.js</code>, using <code>src/lovemap.lua</code> (16:9 virtual 1600x900 coordinates) and <code>src/moonshine/</code> shaders.</p><div class=\"grid\">" + card_html + "</div></div></body></html>")'

## Build WASM and start a local HTTP server to test in the browser
serve: wasm
	@echo "Serving $(WASM_DIR) at http://localhost:$(PORT) (Examples Hub: http://localhost:$(PORT)/examples/)"
	python3 -m http.server $(PORT) --directory "$(WASM_DIR)"

## Remove build artifacts
clean:
	rm -rf "$(BUILD_DIR)" dist

help:
	@echo "Available targets:"
	@echo "  make run           - Run the main game locally using LÖVE"
	@echo "  make love          - Package the main game into $(LOVE_FILE)"
	@echo "  make wasm          - Build main game + all 6 examples to WASM in $(WASM_DIR)"
	@echo "  make wasm-examples - Build only the 6 examples to WASM in $(WASM_DIR)/examples"
	@echo "  make serve         - Build WASM and serve at http://localhost:$(PORT)"
	@echo "  make clean         - Remove build artifacts"
