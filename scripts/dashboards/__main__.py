"""Writes the dashboards into a directory: python3 -m scripts.dashboards infrastructure/configs/monitoring/dashboards

Edit the modules, never the JSON (CI regenerates and compares). Each dashboard is one module with a build()."""
import json
import pathlib
import sys

from . import health, logs, releases, rollout

out = pathlib.Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for module, name in ((health, "health"), (releases, "releases"), (rollout, "rollout"), (logs, "logs")):
    dash = module.build()
    (out / f"{name}.json").write_text(json.dumps(dash, indent=1, ensure_ascii=False) + "\n")
    print(f"{name}.json: {sum(p['type'] != 'row' for p in dash['panels'])} panels")
