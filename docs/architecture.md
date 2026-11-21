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

The current build uses real roads in the city map; world/country map coverage and road-following routing are still incomplete. The current prototype travel movement is visibly identified in its order card as not yet road-routed. Next, build a memory-bounded local graph from the bundled OSM way IDs, then test route and marker alignment at all six viewports before adding more regions. Do not claim road-following until a route actually follows the graph. References: [OSM attribution](https://www.openstreetmap.org/copyright/attribution-guide), [OSM tile policy](https://operations.osmfoundation.org/policies/tiles/), [Geofabrik Malaysia extracts](https://download.geofabrik.de/asia/malaysia-singapore-brunei/).

## Current limitations

The job system, route graph, service companies, financial statements, workforce automation, localization, and expansion are not yet implemented. Existing normalized saves remain on the explicitly labeled fictional map; new sessions use the OSM-derived central Klang Valley map. The accounting journal and fixed-step clock are tested modules but are not yet the runtime source of truth. Current geographic coverage does not include other Malaysian cities, and global/country overview maps are unavailable. The product redesign remains incomplete.
