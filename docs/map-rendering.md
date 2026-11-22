# Geographic map rendering

The browser build uses locally bundled MapLibre GL JS 5.24.0 to render the basemap. Godot continues to own gameplay, the KL/Selangor OSM road graph, route simulation, and map markers. The bridge keeps the MapLibre WGS84 camera synchronized with Godot's Web Mercator route coordinates. MapLibre's CSS attribution is kept visible over the game interface.

## Data and terms

The game uses OpenFreeMap's public MapLibre styles and vector tiles:

- Styles: `https://tiles.openfreemap.org/styles/dark` and `https://tiles.openfreemap.org/styles/positron`.
- The service documents the public instance as free for production use without registration, API keys, or request limits; confirm current terms before materially scaling traffic.
- Source data: OpenStreetMap contributors, licensed under the Open Database License (ODbL); MapLibre's expanded attribution control displays OpenFreeMap, OpenMapTiles, and OSM credit.
- MapLibre GL JS: BSD 3-Clause; the vendored license is `web/vendor/MAPLIBRE-LICENSE.txt`.

The map requests the current viewport only. The game does not bulk-download, prefetch, or bundle map tiles, and it does not bypass provider cache headers. OpenFreeMap operates a public service with no paid key requirement; its documented no-request-limit policy is not an SLA or guaranteed availability. Monitor the provider terms and service status as traffic grows. No paid API key or Cloudflare dependency is used.

The OpenFreeMap vector source provides detailed global basemap data with its published maximum zoom. The Godot routing network remains the separate KL/Selangor dataset; basemap coverage elsewhere does not imply playable routing coverage there.
