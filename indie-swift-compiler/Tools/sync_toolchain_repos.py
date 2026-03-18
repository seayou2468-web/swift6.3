#!/usr/bin/env python3
import argparse
import json
import subprocess
from pathlib import Path


def run(cmd: list[str], cwd: Path | None = None) -> None:
    subprocess.run(cmd, cwd=str(cwd) if cwd else None, check=True)


def is_commit_ref(ref: str) -> bool:
    return len(ref) in {40, 64} and all(ch in "0123456789abcdef" for ch in ref.lower())


def ensure_repo(root: Path, name: str, remote: str, ref: str, depth: int, fetch_tags: bool) -> None:
    path = root / name
    clone_cmd = ["git", "clone"]
    if depth > 0:
        clone_cmd += ["--depth", str(depth), "--single-branch"]
    if not fetch_tags:
        clone_cmd += ["--no-tags"]
    clone_cmd += ["--branch", ref, remote, str(path)]

    if not path.exists():
        run(clone_cmd)

    fetch_cmd = ["git", "fetch", "origin"]
    if depth > 0:
        fetch_cmd += ["--depth", str(depth)]
    if not fetch_tags:
        fetch_cmd += ["--no-tags"]
    if not is_commit_ref(ref):
        fetch_cmd.append(ref)
    run(fetch_cmd, cwd=path)
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
    depth = int(config.get("clone-depth", config.get("fetch-depth", 1)))
    fetch_tags = bool(config.get("fetch-tags", False))

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
        print(f"sync {name}: {ref} (depth={depth}, fetch_tags={fetch_tags})")
        ensure_repo(workspace, name, remote_url, ref, depth, fetch_tags)

    print(f"同期完了: {workspace}")


if __name__ == "__main__":
    main()
