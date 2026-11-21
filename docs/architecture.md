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

## Geographic implementation decision

Real streets and routable geometry are required; the current map is explicitly a fictional prototype and does not meet that requirement. OpenStreetMap-derived data is a viable source under ODbL with attribution and share-alike obligations. OSM public tile servers have a usage policy and are not an unlimited production tile CDN. Malaysia Geofabrik extracts are hundreds of megabytes and are unsuitable as a full-detail initial mobile download. The public OSRM demo is for testing, not production hosting. OpenFreeMap is excluded because its published delivery infrastructure references Cloudflare, contrary to the project constraint.

Next geographic implementation should establish a provider interface, choose a legally permitted tile delivery/cache arrangement, then scope/cache KL/Selangor road data and build an on-device route graph. Do not label schematic roads as geographic or claim road-following until route geometry actually exists. Any map must show OSM attribution and include licensing notices. Usage policy references: [OSM attribution](https://www.openstreetmap.org/copyright/attribution-guide), [OSM tile policy](https://operations.osmfoundation.org/policies/tiles/), [Geofabrik Malaysia extracts](https://download.geofabrik.de/asia/malaysia-singapore-brunei/).

## Current limitations

The job system, geographic map, service companies, financial statements, workforce automation, localization, and expansion are not yet implemented by this foundation. The existing game still has one parcel loop and a fictional map. The new clock and ledger are tested modules but are not yet the runtime source of truth. Milestone 1 should not be described as the complete product redesign.
