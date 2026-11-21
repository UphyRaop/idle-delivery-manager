# Idle Delivery Manager

Mobile-first delivery management tycoon built with Godot 4. The starter scene shows the game title on a dark background. Gameplay will be added separately.

## Develop locally

1. Install the standard Godot **4.5.1** editor and matching export templates. In the editor, use **Editor → Manage Export Templates** to install the templates.
2. Open `project.godot` and press **F6** with `scenes/main.tscn` open, or **F5** to run the project.
3. To test the Web build, run the following commands from the repository root. Set `GODOT_BIN` if your editor executable has a different name or path.

   ```sh
   ./scripts/export-web.sh
   python3 -m http.server 8000 --directory build/web
   ```

4. Open `http://localhost:8000` in a WebGL 2-capable browser. Use a portrait mobile viewport or connect from a phone on the same network using the computer's LAN address.

The project uses a 360 × 640 portrait viewport and preserves its aspect ratio on resize. The Compatibility renderer and single-threaded Web export work on static hosting without cross-origin isolation headers.

## Project structure

- `project.godot` and `scenes/main.tscn` define the project and its entry scene.
- `export_presets.cfg` defines the Web export.
- `scripts/export-web.sh` imports, exports, and verifies the game. It stages the generated HTML, JavaScript, WebAssembly, game pack, and Pages files in `build/web`.
- `.github/workflows/pages.yml` builds pull requests and uploads the export as the `github-pages` artifact. Pushes to `main` and manual runs on `main` also deploy that artifact.

## GitHub Pages

1. In **Settings → Pages**, set **Build and deployment → Source** to **GitHub Actions**.
2. Set **Custom domain** in Pages settings to `idm.ur-project.biz`. The root `CNAME` is included in the artifact. GitHub Pages requires its domain setting for Actions deployments.
3. If the `github-pages` environment requires reviewers, approve the deployment run in **Actions**. Apply any repository or organization Actions approvals required by your policy.
4. After DNS validation and certificate issuance, enable **Enforce HTTPS** and verify that the game loads at [idm.ur-project.biz](https://idm.ur-project.biz/).

The subdomain's DNS CNAME should point to `uphyraop.github.io`.
