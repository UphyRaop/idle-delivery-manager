#!/usr/bin/env python3
"""Build a compact directed OSM routing graph for the bundled KL/Selangor area.

Requires pyosmium (`pip install osmium`). Only roads in the configured bbox are
included. The output stores every routable road node and directed edge, so the
game can render the actual road geometry returned by A*.
"""
from __future__ import annotations

import argparse
from array import array
import gzip
import math
from pathlib import Path
import struct
import osmium

ROAD_CLASSES = {
    "motorway": 0, "motorway_link": 0,
    "trunk": 1, "trunk_link": 1,
    "primary": 2, "primary_link": 2,
    "secondary": 3, "secondary_link": 3,
    "tertiary": 4, "tertiary_link": 4,
    "unclassified": 5, "residential": 5, "living_street": 5,
    "service": 6, "road": 5,
}


class Extract(osmium.SimpleHandler):
    def __init__(self, bbox: tuple[float, float, float, float]) -> None:
        super().__init__()
        self.west, self.south, self.east, self.north = bbox
        self.coords: dict[int, int] = {}
        self.sources = array("Q")
        self.targets = array("Q")
        self.classes = bytearray()
        self.rejected = {"outside": 0, "access": 0, "unsupported": 0}

    def way(self, way: osmium.osm.Way) -> None:
        highway = way.tags.get("highway", "")
        road_class = ROAD_CLASSES.get(highway)
        if road_class is None:
            self.rejected["unsupported"] += 1
            return
        access = way.tags.get("motor_vehicle", way.tags.get("vehicle", way.tags.get("access", "")))
        if access in {"no", "private"}:
            self.rejected["access"] += 1
            return

        oneway = way.tags.get("oneway", "").lower()
        if oneway in {"yes", "1", "true"} or (not oneway and (highway == "motorway" or way.tags.get("junction") == "roundabout")):
            direction = 1
        elif oneway in {"-1", "reverse"}:
            direction = -1
        else:
            direction = 0

        points: list[tuple[int, int, int]] = []
        for node in way.nodes:
            location = node.location
            if not location.valid() or not (
                self.west <= location.lon <= self.east and self.south <= location.lat <= self.north
            ):
                self.rejected["outside"] += 1
                self._connect(points, road_class, direction)
                points = []
                continue
            lat_e6 = round(location.lat * 1_000_000)
            lon_e6 = round(location.lon * 1_000_000)
            self.coords[node.ref] = ((lat_e6 & 0xFFFFFFFF) << 32) | (lon_e6 & 0xFFFFFFFF)
            points.append((node.ref, lat_e6, lon_e6))

        self._connect(points, road_class, direction)

    def _connect(self, points: list[tuple[int, int, int]], road_class: int, direction: int) -> None:
        # Called on clipped chunks. direction is applied by the caller after
        # the way has been read; chunks crossing the bbox are retained only
        # when they still contain a real consecutive road segment.
        if len(points) < 2:
            return
        for first, second in zip(points, points[1:]):
            if direction >= 0:
                self.sources.append(first[0]); self.targets.append(second[0]); self.classes.append(road_class)
            if direction <= 0:
                self.sources.append(second[0]); self.targets.append(first[0]); self.classes.append(road_class)


def distance_m(a: int, b: int) -> int:
    lat1 = (a >> 32) & 0xFFFFFFFF
    lon1 = a & 0xFFFFFFFF
    lat2 = (b >> 32) & 0xFFFFFFFF
    lon2 = b & 0xFFFFFFFF
    if lat1 & 0x80000000: lat1 -= 0x100000000
    if lon1 & 0x80000000: lon1 -= 0x100000000
    if lat2 & 0x80000000: lat2 -= 0x100000000
    if lon2 & 0x80000000: lon2 -= 0x100000000
    lat1 /= 1_000_000; lon1 /= 1_000_000
    lat2 /= 1_000_000; lon2 /= 1_000_000
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1) * math.cos(math.radians((lat1 + lat2) / 2))
    return max(1, round(6_371_000 * math.hypot(dlat, dlon)))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--bbox", nargs=4, type=float, default=(101.55, 2.98, 101.83, 3.30),
                        metavar=("WEST", "SOUTH", "EAST", "NORTH"))
    args = parser.parse_args()
    bbox = tuple(args.bbox)
    extract = Extract(bbox)  # type: ignore[arg-type]
    extract.apply_file(str(args.pbf), locations=True)

    # The arrays keep memory bounded while translating OSM IDs to CSR indices.
    node_ids = sorted(extract.coords)
    index = {node_id: i for i, node_id in enumerate(node_ids)}
    arcs: list[list[tuple[int, int, int]]] = [[] for _ in node_ids]
    for source_id, target_id, road_class in zip(extract.sources, extract.targets, extract.classes):
        source = index.get(source_id)
        target = index.get(target_id)
        if source is None or target is None:
            continue
        meters = distance_m(extract.coords[source_id], extract.coords[target_id])
        arcs[source].append((target, meters, road_class))

    offsets = array("I", [0])
    for outgoing in arcs:
        outgoing.sort(key=lambda edge: edge[0])
        offsets.append(offsets[-1] + len(outgoing))
    arc_count = offsets[-1]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    compressed_output = args.output.name.endswith(".gz")
    raw_output = args.output.with_suffix("") if compressed_output else args.output
    with raw_output.open("wb") as output:
        output.write(b"IDMG")
        output.write(struct.pack("<H4dII", 1, *bbox, len(node_ids), arc_count))
        for node_id in node_ids:
            packed = extract.coords[node_id]
            lat = (packed >> 32) & 0xFFFFFFFF
            lon = packed & 0xFFFFFFFF
            output.write(struct.pack("<ii", lat if lat < 0x80000000 else lat - 0x100000000,
                                     lon if lon < 0x80000000 else lon - 0x100000000))
        output.write(offsets.tobytes())
        for outgoing in arcs:
            for target, meters, road_class in outgoing:
                if meters > 0xFFFFFFFF:
                    raise ValueError("OSM road segment length does not fit in the graph format")
                output.write(struct.pack("<IIB", target, meters, road_class))
    raw_size = raw_output.stat().st_size
    if compressed_output:
        with args.output.open("wb") as bundle:
            bundle.write(struct.pack("<I", raw_size))
            with raw_output.open("rb") as source, gzip.GzipFile(
                filename="", fileobj=bundle, mode="wb", compresslevel=9, mtime=0
            ) as compressed:
                while chunk := source.read(1024 * 1024):
                    compressed.write(chunk)
        raw_output.unlink()
    metadata = {
        "schema": 1, "format": "IDMG directed CSR", "source": "OpenStreetMap via Geofabrik",
        "license": "ODbL-1.0", "bbox_wsen": bbox,
        "nodes": len(node_ids), "directed_arcs": arc_count,
        "oneway_policy": "OSM oneway tags; motorway and roundabout defaults; two-way otherwise",
        "rejected_ways": extract.rejected,
        "encoding": "u32 little-endian raw size + gzip" if compressed_output else "raw",
        "bytes": raw_size,
        "bundle_bytes": args.output.stat().st_size,
    }
    metadata_path = args.output.with_suffix("").with_suffix(".metadata.json") if compressed_output else args.output.with_suffix(".metadata.json")
    metadata_path.write_text(__import__("json").dumps(metadata, indent=2) + "\n")
    print(f"Wrote {len(node_ids):,} nodes / {arc_count:,} directed arcs ({args.output.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
