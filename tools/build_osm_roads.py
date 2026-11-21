#!/usr/bin/env python3
"""Build compact local OSM roads and map textures from a Geofabrik PBF.

Usage: pip install osmium pillow; python tools/build_osm_roads.py extract.osm.pbf data/kl_selangor_roads.bin
"""
import argparse
import json
from pathlib import Path
import struct
import osmium
from PIL import Image, ImageDraw, ImageFont

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
    def __init__(self, bbox):
        super().__init__()
        self.west, self.south, self.east, self.north = bbox
        self.ways = []
        self.places = []
    def node(self, node):
        place = node.tags.get("place", "")
        name = node.tags.get("name") or node.tags.get("name:en") or node.tags.get("name:ms")
        if place in {"city", "town", "suburb", "neighbourhood", "quarter", "village"} and name and node.location.valid():
            if self.west <= node.location.lon <= self.east and self.south <= node.location.lat <= self.north:
                self.places.append({"name": name, "type": place, "lat_e6": round(node.location.lat * 1_000_000), "lon_e6": round(node.location.lon * 1_000_000)})
    def way(self, way):
        road_class = ROAD_CLASSES.get(way.tags.get("highway", ""))
        if road_class is None:
            return
        points = []
        for node in way.nodes:
            loc = node.location
            inside = loc.valid() and self.west <= loc.lon <= self.east and self.south <= loc.lat <= self.north
            if inside:
                points.append((node.ref, loc.lat, loc.lon))
            else:
                self.append(way, road_class, points)
                points = []
        self.append(way, road_class, points)
    def append(self, way, road_class, points):
        if len(points) < 2:
            return
        name = way.tags.get("name") or way.tags.get("name:en") or way.tags.get("name:ms") or ""
        self.ways.append((road_class, name, points))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--bbox", nargs=4, type=float, default=[101.55, 2.98, 101.83, 3.30], metavar=("WEST", "SOUTH", "EAST", "NORTH"))
    args = parser.parse_args()
    west, south, east, north = args.bbox
    extract = Extract(args.bbox)
    extract.apply_file(str(args.pbf), locations=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Reusable geometry for future network routing; node IDs preserve OSM connectivity.
    with args.output.open("wb") as stream:
        stream.write(b"IDMR")
        stream.write(struct.pack("<H4dI", 1, west, south, east, north, len(extract.ways)))
        for road_class, name, points in extract.ways:
            encoded = name.encode("utf-8")[:255]
            stream.write(struct.pack("<BBI", road_class, len(encoded), len(points)))
            stream.write(encoded)
            for node_id, lat, lon in points:
                stream.write(struct.pack("<Qii", node_id, round(lat * 1_000_000), round(lon * 1_000_000)))

    # Deterministic delivery-eligible road nodes; use only lower classes so a
    # generated booking does not appear on an access-controlled motorway.
    spawn_nodes = {}
    for road_class, _name, points in extract.ways:
        if road_class >= 4:
            for node_id, lat, lon in points:
                spawn_nodes[node_id] = (round(lat * 1_000_000), round(lon * 1_000_000))
    ordered_spawns = [spawn_nodes[key] for key in sorted(spawn_nodes)]
    if len(ordered_spawns) > 5000:
        step = len(ordered_spawns) / 5000
        ordered_spawns = [ordered_spawns[int(index * step)] for index in range(5000)]
    args.output.with_name("kl_selangor_spawns.json").write_text(json.dumps(ordered_spawns, separators=(",", ":")))
    args.output.with_name("kl_selangor_places.json").write_text(json.dumps(extract.places, separators=(",", ":"), ensure_ascii=False))

    # Render a pre-scaled base texture so the Web game does not parse/draw a
    # million GIS objects on every frame. World-to-texture uses Web Mercator.
    width, height = 1152, 1320
    def project(lat, lon):
        x = (lon - west) / (east - west) * width
        merc_n = lambda value: __import__("math").log(__import__("math").tan(__import__("math").pi / 4 + __import__("math").radians(value) / 2))
        y = (1 - (merc_n(lat) - merc_n(south)) / (merc_n(north) - merc_n(south))) * height
        return round(x), round(y)
    styles = [
        (("#b3e7f2", "#176b84"), 7), (("#8fcbd8", "#237c92"), 6),
        (("#78acba", "#33899b"), 5), (("#5f8491", "#5c969f"), 4),
        (("#486774", "#8aaeb2"), 3), (("#304753", "#b7c9c8"), 2),
        (("#233743", "#cedbda"), 1),
    ]
    for mode, background in [("dark", "#0b1720"), ("light", "#e7eeec")]:
        image = Image.new("RGB", (width, height), background)
        draw = ImageDraw.Draw(image)
        for road_class in range(6, -1, -1):
            color, line_width = styles[road_class][0][0 if mode == "dark" else 1], styles[road_class][1]
            for feature_class, _name, points in extract.ways:
                if feature_class != road_class:
                    continue
                pixels = [project(lat, lon) for _node_id, lat, lon in points]
                draw.line(pixels, fill=color, width=line_width, joint="curve")
        image.save(args.output.with_name(f"kl_selangor_{mode}.png"), optimize=True)
    metadata = {
        "schema": 1,
        "source": "OpenStreetMap contributors via Geofabrik Malaysia-Singapore-Brunei extract",
        "extract_date": "2026-11-21",
        "license": "Open Database License (ODbL) 1.0",
        "bbox_wsen": args.bbox,
        "texture_px": [width, height],
        "road_segments": len(extract.ways),
        "place_labels": len(extract.places),
        "spawn_points": len(ordered_spawns),
    }
    args.output.with_suffix(".metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Wrote {len(extract.ways):,} road segments to {args.output} ({args.output.stat().st_size:,} bytes)")
    print(f"Textures: {args.output.with_name('kl_selangor_dark.png')} and _light.png")

if __name__ == "__main__":
    main()
