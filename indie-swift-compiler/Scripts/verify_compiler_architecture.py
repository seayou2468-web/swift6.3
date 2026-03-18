#!/usr/bin/env python3
import json
from pathlib import Path


EXPECTED = [
    "swift",
    "swift-frontend",
    "sil-optimizer-mandatory",
    "sil-optimizer-performance",
    "irgen",
]


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    manifest_path = root / "Config" / "compiler-pipeline.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    stage_order = manifest.get("stageOrder", [])

    if stage_order != EXPECTED:
        raise SystemExit(
            f"pipeline stage order mismatch: expected {EXPECTED}, got {stage_order}"
        )

    stages = manifest.get("stages", {})
    for index, name in enumerate(EXPECTED):
        if name not in stages:
            raise SystemExit(f"missing pipeline stage definition: {name}")
        if index > 0:
            expected_dep = EXPECTED[index - 1]
            deps = stages[name].get("dependsOn", [])
            if expected_dep not in deps:
                raise SystemExit(f"{name} is not connected from {expected_dep}: {deps}")

    print("compiler architecture verified:", " -> ".join(stage_order))


if __name__ == "__main__":
    main()
