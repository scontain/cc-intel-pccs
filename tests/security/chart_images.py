#!/usr/bin/env python3
"""Print the chart's actual default image reference, without rendering secrets."""
import sys
from pathlib import Path

import yaml

values = yaml.safe_load(Path("charts/pccs/values.yaml").read_text())
component = sys.argv[1]
if component not in ("pccs", "fluentbit"):
    raise SystemExit("Expected pccs or fluentbit")
image = values["image"] if component == "pccs" else values["fluentbit"]["image"]
print(f"{image['repository']}:{image['tag']}")
