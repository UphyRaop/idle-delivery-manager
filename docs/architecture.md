# IDM architecture and migration baseline

This note records the shared contracts introduced for the 100-requirement redesign. The current playable prototype remains an integration baseline; the new service classes are foundations and are not yet wired into all game screens.

## Module boundaries

| Module | Current contract | Planned owner |
| --- | --- | --- |
| `scripts/game.gd` | Current screen/input adapter and legacy gameplay loop | UI integration only as systems are extracted |
| `scripts/services/simulation_clock.gd` | Fixed 100 ms simulation ticks; Pause and 1×/2×/5×/10×; rendering delta never directly changes domain outcomes | Simulation |
| `scripts/domain/ledger_service.gd` | Idempotent transaction ID, company/source IDs, balanced debit/credit lines in integer sen | Finance |
| `scripts/services/save_repository.gd` | Versioned schema validation, pure legacy migration, three slot API, verified temp write and backup | Persistence |
| `scripts/services/theme_service.gd` | Dark/light color tokens and persistent preference | UI |
| `GeoPoint` (contract) | WGS84 latitude/longitude in decimal degrees, named coordinate-space metadata for non-geographic legacy points | Geography |
| `Job` (contract) | Stable ID, service/company, lifecycle state, pickup/drop-off references, assignment, quote and settlement IDs | Simulation |
| `Partner` (contract) | Independent contractor, vehicle registry, availability, rating/reliability, location and earnings | Workforce |

Gameplay domain services must communicate through events carrying stable IDs (for example `booking_created`, `job_assigned`, `job_completed`, `settlement_posted`). Settlement and ledger writes must be idempotent on those IDs. UI must read system state and must not independently calculate accounting totals.

## Save safety

The current v1 single-company JSON is still the active compatibility format for the existing playable loop. `IDMSaveRepository.migrate_legacy_v1` is a pure, tested adapter to a v2 holding-group representation. It preserves cash/revenue/cost/delivery totals as historical totals without fabricating journal lines. Old normalized map coordinates remain explicitly `legacy_normalized`, not latitude/longitude. Old riders are represented as independent partners with an explicitly flagged motorcycle migration assumption.

V2 provides three manual slots, validation, write-to-temp/read-back verification, and a `.bak` before replacement. The live prototype will not silently auto-migrate or overwrite a legacy file. If its save is unreadable, it pauses and offers Retry or a separate recovery session, retaining the original bytes. Browser storage quota and interrupted Web writes still need device/browser QA.

## Geographic implementation decision and first extract

The new-game map now displays a bundled, locally rendered OpenStreetMap-derived street map for the central Kuala Lumpur / Selangor coverage box. Road and locality records come from the Geofabrik Malaysia-Singapore-Brunei extract dated 2026-11-21, under ODbL, with on-screen and repository attribution. Map generation is reproducible with `tools/build_osm_roads.py`; it creates dark/light map textures, locality labels, road-based spawn points, and a compact OSM way-geometry file.

The service does not fetch public tiles at runtime. A request to `tile.openstreetmap.org` was denied with the service's usage-policy response, and public tile servers are not an unlimited production tile CDN. Malaysia Geofabrik extracts are hundreds of megabytes, so only the central KL/Selangor box is included in the current client build. The public OSRM demo is for testing, not production hosting. OpenFreeMap is excluded because its published delivery infrastructure references Cloudflare, contrary to the project constraint.

The current build uses real roads in the city map and a local, memory-bounded directed routing graph for central Kuala Lumpur and central Selangor. The game does not fetch public tiles or call a public routing server at runtime. References: [OSM attribution](https://www.openstreetmap.org/copyright/attribution-guide), [OSM tile policy](https://operations.osmfoundation.org/policies/tiles/), [Geofabrik Malaysia extracts](https://download.geofabrik.de/asia/malaysia-singapore-brunei/).

## Road-routing increment

`IDMRoadRouter` reads `data/kl_selangor_route_graph.bin.gz`, a directed CSR graph built by `tools/build_routing_graph.py` from the same Geofabrik OSM extract. The size-prefixed gzip bundle is 6.9 MB, versus 14.7 MB raw, and is decompressed once at startup. It retains OSM one-way and access semantics. `route_between_uv` snaps both ends to the graph, runs A* using class-based estimated travel times, and returns the road-node polyline plus exact graph distance and per-edge ETA. A route outside the local graph, over a disconnected component, or beyond the 2 m snap threshold fails closed. The game does not fall back to a straight-line route.

`IDMRouteSimulation` serializes versioned route geometry and progress for the current-location → pickup → destination legs. Existing geographic saves from before routed trips that lack route state are safely requeued and their partner is released. Legacy fictional normalized-coordinate saves remain in their own map mode; those coordinates are never reinterpreted as WGS84. The map camera helper owns the transform used by roads, markers, hit testing, zoom, pan, and rider follow.

Current routing coverage remains central KL/Selangor only (graph bounds 101.55°–101.83° E, 2.98°–3.30° N). The 14.7 MB raw graph has no online service dependency; Web transfer size must be verified from the final export. Other Malaysian cities, live traffic, time-of-day routing, toll alternatives, and broad national route coverage are future work. Class speeds are gameplay estimates, not live or official ETAs.

## Current limitations

The broader service-company/job system, financial statements, workforce automation, localization, and expansion are not yet implemented. Existing normalized saves remain on the explicitly labeled fictional map; new sessions use the OSM-derived central Klang Valley map with road-following dispatch. The accounting journal and fixed-step clock are tested modules but are not yet the runtime source of truth. Current geographic coverage does not include other Malaysian cities, and global/country overview maps are unavailable. The product redesign remains incomplete.
