# Geographic map rendering

The browser build uses locally bundled MapLibre GL JS 5.24.0 to render the basemap. Godot continues to own gameplay, the KL/Selangor OSM road graph, route simulation, and map markers. The bridge keeps the MapLibre WGS84 camera synchronized with Godot's Web Mercator route coordinates. MapLibre's CSS attribution is kept visible over the game interface.

## Data and terms

The current public style and vector tiles are served by the OpenStreetMap Foundation Shortbread vector tile service:

- Style: `https://vector.openstreetmap.org/styles/shortbread/eclipse.json` (dark) and `colorful.json` (light).
- TileJSON: `https://vector.openstreetmap.org/shortbread_v1/tilejson.json`.
- Source data: OpenStreetMap contributors, licensed under the Open Database License (ODbL); attribution is shown in the map control.
- MapLibre GL JS: BSD 3-Clause; the vendored license is `web/vendor/MAPLIBRE-LICENSE.txt`.

The map requests the current viewport only. The game does not bulk-download, prefetch, or bundle OSM tiles, and it does not bypass the provider cache headers. The OSMF vector service is a community-provided best-effort service without a production SLA or guaranteed capacity. Do not treat it as unlimited hosting; monitor its published usage policy and migrate to an explicitly permitted provider if traffic grows beyond ordinary interactive use. No paid API key or Cloudflare dependency is used.

The OSMF shortbread tiles currently advertise maximum zoom 14. MapLibre permits smooth overzoom beyond that level, but no extra source detail appears above the tile data maximum. The Godot routing network remains the separate KL/Selangor dataset; basemap coverage elsewhere does not imply playable routing coverage there.
