import json
from pathlib import Path
import struct
import sys
import xml.etree.ElementTree as ET

root = Path(sys.argv[1] if len(sys.argv) > 1 else "build/web")
html = (root / "index.html").read_text()
manifest = json.loads((root / "manifest.webmanifest").read_text())
game_script = Path("scripts/game.gd").read_text()
app_icon = ET.parse(root / "brand/idm-app-icon.svg").getroot()
favicon = ET.parse(root / "favicon.svg").getroot()
logo = ET.parse(root / "brand/idm-logo.svg").getroot()
checks = {
    "web metadata links svg/png/ico/favicon/apple touch/manifest": all(
        token in html
        for token in (
            "./favicon.svg",
            "./brand/icons/idm-icon-32.png",
            "./brand/icons/favicon.ico",
            "./brand/icons/idm-icon-180.png",
            "./manifest.webmanifest",
            'name="apple-mobile-web-app-title" content="IDM"',
        )
    ),
    "manifest declares app identity and install icons": (
        manifest.get("name") == "Idle Delivery Manager"
        and {item.get("sizes") for item in manifest.get("icons", [])} == {"192x192", "512x512"}
        and all((root / item["src"].removeprefix("./")).is_file() for item in manifest["icons"])
    ),
    "standalone game icon and favicon use approved dark teal/cyan mark": (
        app_icon.attrib.get("viewBox") == "0 0 512 512"
        and favicon.attrib.get("viewBox") == "0 0 512 512"
        and any(node.attrib.get("fill") == "#113B48" for node in app_icon)
        and any(node.attrib.get("stroke") == "#55D9E8" for node in app_icon)
        and any(node.attrib.get("stroke") == "#55D9E8" for node in favicon)
    ),
    "full logo has accessible title and requested identity": (
        any(node.tag.endswith("title") and node.text == "IDLE DELIVERY MANAGER" for node in logo)
        and logo.attrib.get("width") == "920"
        and logo.attrib.get("height") == "192"
        and any(node.attrib.get("aria-label") == "IDLE DELIVERY MANAGER" for node in logo.iter())
        and any(node.attrib.get("aria-label") == "Build Your Logistics Empire" for node in logo.iter())
    ),
    "main menu loads the full vector logo asset": 'load("res://assets/branding/idm-logo.svg")' in game_script,
    "raster icon dimensions match platform contracts": True,
    "desktop ico is valid": False,
}

expected_sizes = {16, 32, 48, 180, 192, 512}
actual_sizes = set()
for png in (root / "brand/icons").glob("idm-icon-*.png"):
    data = png.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        width, height = struct.unpack(">II", data[16:24])
        if width == height:
            actual_sizes.add(width)
checks["raster icon dimensions match platform contracts"] = actual_sizes == expected_sizes
ico = (root / "brand/icons/favicon.ico").read_bytes()
checks["desktop ico is valid"] = ico[:4] == b"\x00\x00\x01\x00"

failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
print(f"BRANDING ASSETS RESULT: {len(checks) - len(failed)} passed, {len(failed)} failed")
sys.exit(1 if failed else 0)
