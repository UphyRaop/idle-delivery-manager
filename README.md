# IDLE DELIVERY MANAGER

Mobile-first delivery management tycoon built with Godot 4.5.1. Startup opens the branded New Game / Continue / Load Game / Settings menu. Geographic saves use an interactive OpenStreetMap basemap with KL/Selangor road routing; legacy saves remain isolated on their fictional map to preserve their coordinate data. The game uses touch-friendly booking markers, an expanding management sheet, and persistent bottom navigation.

Continue selects the valid save with the newest saved_at timestamp. Older saves without a timestamp fall back to their profile creation time. New Game creates a separate geographic save profile and leaves existing profiles available through Load Game.

## Develop locally

1. Install the standard Godot **4.5.1** editor and matching export templates. In the editor, use **Editor → Manage Export Templates** to install the templates.
2. Open `project.godot` and press **F6** with `scenes/main.tscn` open, or **F5** to run the project.
3. To test the Web build, run the following commands from the repository root. Set `GODOT_BIN` if your editor executable has a different name or path.

   ```sh
   ./scripts/export-web.sh
   python3 -m http.server 8000 --directory build/web
   ```

4. Open `http://localhost:8000` in a WebGL 2-capable browser. Use a portrait mobile viewport or connect from a phone on the same network using the computer's LAN address.

The project starts from a 390 × 844 portrait viewport and supports sensor-based rotation. Web layout follows the available browser viewport, disables page scrolling, and reads iOS safe-area insets. The Compatibility renderer and single-threaded Web export work on static hosting without cross-origin isolation headers.

Map renderer and public tile-provider terms are documented in [docs/map-rendering.md](docs/map-rendering.md).

## Project structure

- `project.godot` and `scenes/main.tscn` define the project and its entry scene.
- `export_presets.cfg` defines the Web export.
- `scripts/export-web.sh` imports, exports, and verifies the game. It stages the generated HTML, JavaScript, WebAssembly, game pack, and Pages files in `build/web`.
- `.github/workflows/pages.yml` builds pull requests and uploads the export as the `github-pages` artifact. Pushes to `main` and manual runs on `main` also deploy that artifact.
- `scripts/domain/` and `scripts/services/` contain the staged domain foundations (integer-sen ledger, fixed-step clock, versioned save adapter, theme tokens).
- `tests/run_tests.gd` is the headless regression runner for those foundations. Run it with `godot --headless --path . --script tests/run_tests.gd`.
- `docs/architecture.md` records module contracts, migration safety, and the geographic data decision.

The Web export script also injects the branded startup loader into each clean export. It uses Godot's real download progress, displays an indeterminate indicator when no total is available, respects reduced motion, and offers a reload action when startup fails.

## GitHub Pages

1. In **Settings → Pages**, set **Build and deployment → Source** to **GitHub Actions**.
2. Set **Custom domain** in Pages settings to `idm.ur-project.biz`. The root `CNAME` is included in the artifact. GitHub Pages requires its domain setting for Actions deployments.
3. If the `github-pages` environment requires reviewers, approve the deployment run in **Actions**. Apply any repository or organization Actions approvals required by your policy.
4. After DNS validation and certificate issuance, enable **Enforce HTTPS** and verify that the game loads at [idm.ur-project.biz](https://idm.ur-project.biz/).

The subdomain's DNS CNAME should point to `uphyraop.github.io`.
