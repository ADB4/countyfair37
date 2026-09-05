#!/usr/bin/env python3
"""contract_check.py — grep CONTRACTS.md against the working tree.

Usage:
    python3 tools/contract_check.py [--repo PATH] [--contracts PATH] [--pending]

Rules (mirroring the header of CONTRACTS.md):
  * Every backticked string under "## Current" must appear, literally
    (whitespace-normalised), somewhere in scripts/, scenes/ or project.godot —
    OR be a path that exists relative to the repo root.
  * Every backticked string under "## Retired" must appear nowhere in
    scripts/ or scenes/ (project.godot excluded: it is not a scene).
  * "## In progress" and "## Planned" are skipped unless --pending is given,
    in which case "## In progress" is checked like Current (useful at a story's
    done-gate, right before promoting its lines).

Exit status: 0 clean, 1 drift found, 2 usage error. Output is plain text
so it reads fine in a ticket comment.
"""
import argparse
import os
import re
import sys

SEARCH_DIRS = ("scripts", "scenes")
SEARCH_FILES = ("project.godot",)
BACKTICK = re.compile(r"`([^`]+)`")


def normalise(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def read_tree(repo: str, include_project_godot: bool) -> dict:
    """Return {relative_path: normalised_text} for every file we search."""
    out = {}
    for d in SEARCH_DIRS:
        root = os.path.join(repo, d)
        for dirpath, _, files in os.walk(root):
            for f in files:
                if f.endswith((".gd", ".tscn", ".tres", ".gdshader")):
                    p = os.path.join(dirpath, f)
                    with open(p, encoding="utf-8", errors="replace") as fh:
                        out[os.path.relpath(p, repo)] = normalise(fh.read())
    if include_project_godot:
        for f in SEARCH_FILES:
            p = os.path.join(repo, f)
            if os.path.exists(p):
                with open(p, encoding="utf-8", errors="replace") as fh:
                    out[f] = normalise(fh.read())
    return out


def split_sections(md: str) -> dict:
    """Map top-level '## ' heading text -> body. '### ' stays inside its parent."""
    sections, current, buf = {}, None, []
    for line in md.splitlines():
        if line.startswith("## ") and not line.startswith("### "):
            if current is not None:
                sections[current] = "\n".join(buf)
            current, buf = line[3:].strip(), []
        else:
            buf.append(line)
    if current is not None:
        sections[current] = "\n".join(buf)
    return sections


def section_named(sections: dict, prefix: str) -> str:
    for k, v in sections.items():
        if k.lower().startswith(prefix.lower()):
            return v
    return ""


def literals(body: str) -> list:
    seen, out = set(), []
    for m in BACKTICK.finditer(body):
        lit = normalise(m.group(1))
        if lit and lit not in seen:
            seen.add(lit)
            out.append(lit)
    return out


def found_in(lit: str, tree: dict) -> list:
    return [path for path, text in tree.items() if lit in text]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".", help="repo root (default: cwd)")
    ap.add_argument("--contracts", default=None, help="path to CONTRACTS.md")
    ap.add_argument("--pending", action="store_true",
                    help="also check '## In progress' as if Current (done-gate)")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    contracts = args.contracts or os.path.join(repo, "CONTRACTS.md")
    if not os.path.exists(contracts):
        print(f"error: {contracts} not found", file=sys.stderr)
        return 2

    with open(contracts, encoding="utf-8") as fh:
        sections = split_sections(fh.read())

    tree_all = read_tree(repo, include_project_godot=True)
    tree_code = {k: v for k, v in tree_all.items() if k not in SEARCH_FILES}

    drift = 0

    def check_present(label: str, body: str):
        nonlocal drift
        missing = []
        for lit in literals(body):
            if os.path.exists(os.path.join(repo, lit)):
                continue  # a path that exists counts as present
            if not found_in(lit, tree_all):
                missing.append(lit)
        if missing:
            drift += len(missing)
            print(f"[{label}] {len(missing)} contract(s) NOT found in code:")
            for m in missing:
                print(f"    - `{m}`")
        else:
            print(f"[{label}] all {len(literals(body))} contracts present")

    check_present("Current", section_named(sections, "Current"))
    if args.pending:
        check_present("In progress", section_named(sections, "In progress"))

    retired_body = section_named(sections, "Retired")
    present = []
    for lit in literals(retired_body):
        hits = found_in(lit, tree_code)
        if hits:
            present.append((lit, hits))
    if present:
        drift += len(present)
        print(f"[Retired] {len(present)} retired name(s) STILL present:")
        for lit, hits in present:
            print(f"    - `{lit}` in {', '.join(sorted(hits))}")
    else:
        print(f"[Retired] all {len(literals(retired_body))} retired names absent")

    print("RESULT:", "clean" if drift == 0 else f"{drift} drift item(s)")
    return 0 if drift == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
