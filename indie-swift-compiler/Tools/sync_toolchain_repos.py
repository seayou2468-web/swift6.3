#!/usr/bin/env python3
import argparse
import json
import subprocess
from pathlib import Path


def run(cmd: list[str], cwd: Path | None = None) -> None:
    subprocess.run(cmd, cwd=str(cwd) if cwd else None, check=True)


def ensure_repo(root: Path, name: str, remote: str, ref: str) -> None:
    path = root / name
    if not path.exists():
        run(["git", "clone", remote, str(path)])
    run(["git", "fetch", "--all", "--tags"], cwd=path)
    run(["git", "checkout", ref], cwd=path)


def main() -> None:
    parser = argparse.ArgumentParser(description="最小toolchain構成JSONからrepo同期")
    parser.add_argument("--config", required=True)
    parser.add_argument("--scheme", required=True)
    parser.add_argument("--workspace", required=True)
    args = parser.parse_args()

    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    repos = config.get("repos", {})
    scheme = config.get("branch-schemes", {}).get(args.scheme, {})
    refs = scheme.get("repos", {})
    clone_pattern = config.get("https-clone-pattern", "https://github.com/%s.git")

    workspace = Path(args.workspace)
    workspace.mkdir(parents=True, exist_ok=True)

    for name, repo_data in repos.items():
        remote_id = repo_data.get("remote", {}).get("id")
        if not remote_id:
            raise SystemExit(f"remote id が不足: {name}")
        if name not in refs:
            raise SystemExit(f"scheme {args.scheme} に ref が不足: {name}")

        remote_url = clone_pattern % remote_id
        ref = refs[name]
        print(f"sync {name}: {ref}")
        ensure_repo(workspace, name, remote_url, ref)

    print(f"同期完了: {workspace}")


if __name__ == "__main__":
    main()
