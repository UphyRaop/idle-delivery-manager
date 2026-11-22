from pathlib import Path
import sys

html = Path(sys.argv[1] if len(sys.argv) > 1 else "build/web/index.html").read_text()
checks = {
    "dark branded loading panel": 'class="idm-loader-card"' in html and "#081722" in html,
    "cyan original truck symbol": 'class="idm-loader-mark"' in html and "<svg" in html,
    "approved loading title and subtitle": "IDLE DELIVERY MANAGER" in html and "Build Your Logistics Empire" in html,
    "creator followed by copyright": html.index("Created by UphyRaop") < html.index("© 2026 UR Trade Network. All rights reserved."),
    "no separate loading publisher line": "idm-loader-company" not in html,
    "determinate progress uses actual loaded bytes": "statusProgress.value = completed" in html and "completed / total * 100" in html,
    "unknown total remains indeterminate": "statusOverlay.dataset.progressMode = 'indeterminate'" in html and "progressFill.style.width = ''" in html,
    "startup errors announce alert and retry": "statusNotice.setAttribute('role', 'alert')" in html and "idm-loading-retry" in html and "window.location.reload()" in html,
    "reduced motion keeps progress visible": "prefers-reduced-motion: reduce" in html and "width: 100%; opacity: .72" in html,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
print(f"LOADING SHELL RESULT: {len(checks) - len(failed)} passed, {len(failed)} failed")
sys.exit(1 if failed else 0)
