#!/usr/bin/env python3
"""Detect a repo's dominant language and route it to a system-developer agent.

Implements the marker -> language -> agent rules in
skills/_shared/language-detection.md (Detection Priority Order, the
Marker/Extension tables, the seven Tie-Breaking Rules, and the >70% census
rule), so the router never re-applies them by hand. Keep this in sync with that
doc — it is the source of truth.

Stdout is the qualified agent (one token, pipeable); the reasoning goes to
stderr. With --json the full verdict (agent, language, confidence, reason,
signals) is printed to stdout instead.

Usage:
    detect_language.py [--path DIR] [--json]

Examples:
    detect_language.py --path .
    detect_language.py --path /repo --json

Exit codes:
    0  a verdict was produced (including the router fallback)
    2  the path does not exist

Dependencies: Python 3.12+ standard library only.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import Counter
from dataclasses import asdict, dataclass, field
from pathlib import Path

# --- marker -> extension classification ------------------------------------

CPP_SOURCE_EXTS = {".cpp", ".cc", ".cxx", ".c++", ".cppm", ".ixx"}
CPP_HEADER_EXTS = {".hpp", ".hh", ".hxx"}
C_SOURCE_EXTS = {".c"}
AMBIGUOUS_HEADER_EXTS = {".h"}  # C unless C++ markers exist (tie-break 2)
PYTHON_EXTS = {".py", ".pyi"}
SHELL_EXTS = {".sh", ".bash", ".bats"}

CENSUS_EXTS = (
    CPP_SOURCE_EXTS
    | CPP_HEADER_EXTS
    | C_SOURCE_EXTS
    | AMBIGUOUS_HEADER_EXTS
    | PYTHON_EXTS
    | SHELL_EXTS
)

# Manifest filenames (presence-based; tiers 2-3 of the priority order).
PY_MANIFESTS = {"pyproject.toml", "uv.lock", "setup.py", "setup.cfg"}
CMAKE_MANIFESTS = {"CMakeLists.txt", "CMakePresets.json"}
MESON_MANIFESTS = {"meson.build"}
CPP_PKG_MANIFESTS = {"vcpkg.json", "conanfile.txt", "conanfile.py"}
SHELL_MANIFESTS = {".shellcheckrc"}

# Substrings that mark a Python project as carrying a native extension
# (tie-break 4: route the mixed repo to the router).
NATIVE_EXTENSION_HINTS = (
    "ext_modules",
    "scikit-build",
    "scikit_build",
    "pybind11",
    "nanobind",
    "cffi",
)

AGENT = {
    "c": "system-developer:c-developer",
    "cpp": "system-developer:cpp-developer",
    "python": "system-developer:python-developer",
    "bash": "system-developer:bash-developer",
    "router": "system-developer:system-developer",
}

# Directories never counted in the census (build output, venvs, vendored code).
PRUNE_DIRS = {
    ".git",
    ".venv",
    "venv",
    "node_modules",
    "__pycache__",
    ".pytest_cache",
    ".ruff_cache",
    ".mypy_cache",
    "vendor",
    "third_party",
    ".worktrees",
}


@dataclass
class Verdict:
    language: str
    agent: str
    confidence: str  # high | medium | low
    reason: str
    signals: dict[str, object] = field(default_factory=dict)


def _is_pruned(rel: Path) -> bool:
    if any(part in PRUNE_DIRS for part in rel.parts):
        return True
    # build, build-asan, build/ ... (the .gitignore convention is build*/)
    return any(part.startswith("build") for part in rel.parts)


def list_source_files(root: Path) -> list[Path]:
    """Tracked files via `git ls-files`, falling back to a pruned walk."""
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files"],
            capture_output=True,
            text=True,
            check=True,
        )
        names = [line for line in out.stdout.splitlines() if line]
        if names:
            return [root / n for n in names if not _is_pruned(Path(n))]
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    files: list[Path] = []
    for p in root.rglob("*"):
        if p.is_file() and not _is_pruned(p.relative_to(root)):
            files.append(p)
    return files


def find_manifests(root: Path, files: list[Path]) -> set[str]:
    """Manifest basenames present anywhere in the tree."""
    wanted = (
        PY_MANIFESTS
        | CMAKE_MANIFESTS
        | MESON_MANIFESTS
        | CPP_PKG_MANIFESTS
        | SHELL_MANIFESTS
    )
    found = {f.name for f in files if f.name in wanted}
    # requirements*.txt is a glob, not a fixed name.
    if any(f.name.startswith("requirements") and f.suffix == ".txt" for f in files):
        found.add("requirements.txt")
    return found


def census(files: list[Path]) -> Counter[str]:
    """Count source files per language bucket, honoring the .h tie-break."""
    ext_counts: Counter[str] = Counter()
    for f in files:
        ext = f.suffix.lower()
        if ext in CENSUS_EXTS:
            ext_counts[ext] += 1

    cpp_sources = sum(ext_counts[e] for e in CPP_SOURCE_EXTS | CPP_HEADER_EXTS)
    lang: Counter[str] = Counter()
    for ext, n in ext_counts.items():
        if ext in CPP_SOURCE_EXTS or ext in CPP_HEADER_EXTS:
            lang["cpp"] += n
        elif ext in C_SOURCE_EXTS:
            lang["c"] += n
        elif ext in AMBIGUOUS_HEADER_EXTS:
            # Bare .h counts as C++ when the tree has C++ sources, else C.
            lang["cpp" if cpp_sources else "c"] += n
        elif ext in PYTHON_EXTS:
            lang["python"] += n
        elif ext in SHELL_EXTS:
            lang["bash"] += n
    return lang


def _cmake_declares_cxx(files: list[Path]) -> bool:
    """True if a CMakeLists.txt names CXX (project(... CXX) / CMAKE_CXX_*)."""
    for f in files:
        if f.name != "CMakeLists.txt":
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if "CMAKE_CXX_STANDARD" in text or "CXX" in text:
            return True
    return False


def _python_has_native(root: Path, files: list[Path], manifests: set[str]) -> bool:
    """Tie-break 4: a Python project that also builds a native extension."""
    has_native_manifest = bool(
        manifests & (CMAKE_MANIFESTS | MESON_MANIFESTS | CPP_PKG_MANIFESTS)
    )
    has_native_sources = any(
        f.suffix.lower() in (C_SOURCE_EXTS | CPP_SOURCE_EXTS) for f in files
    )
    if has_native_manifest or has_native_sources:
        return True
    # setup.py / pyproject with an extension hint, without obvious sources.
    for f in files:
        if f.name in {"setup.py", "pyproject.toml", "setup.cfg"}:
            try:
                text = f.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            if any(hint in text for hint in NATIVE_EXTENSION_HINTS):
                return True
    return False


def detect(root: Path) -> Verdict:
    files = list_source_files(root)
    manifests = find_manifests(root, files)
    lang_counts = census(files)
    signals: dict[str, object] = {
        "manifests": sorted(manifests),
        "census": dict(lang_counts),
    }

    has_python = bool(manifests & PY_MANIFESTS) or "requirements.txt" in manifests
    has_cmake = bool(manifests & CMAKE_MANIFESTS)
    has_meson = bool(manifests & MESON_MANIFESTS)
    has_cpp_pkg = bool(manifests & CPP_PKG_MANIFESTS)
    has_native_manifest = has_cmake or has_meson or has_cpp_pkg
    has_cpp_sources = any(
        f.suffix.lower() in (CPP_SOURCE_EXTS | CPP_HEADER_EXTS) for f in files
    )

    # Tier 2-3: manifests/lockfiles outrank the census.
    if has_python and _python_has_native(root, files, manifests):
        return Verdict(
            "mixed",
            AGENT["router"],
            "high",
            "Python manifest plus native build/sources — FFI/native extension "
            "(tie-break 4); router coordinates per-file work.",
            signals,
        )
    if has_python and not has_native_manifest:
        return Verdict(
            "python", AGENT["python"], "high", "Python manifest present.", signals
        )
    if has_native_manifest:
        if has_cpp_sources or (has_cmake and _cmake_declares_cxx(files)) or has_cpp_pkg:
            return Verdict(
                "cpp",
                AGENT["cpp"],
                "high",
                "CMake/Meson/C++ package manifest with C++ markers (tie-break 1).",
                signals,
            )
        return Verdict(
            "c",
            AGENT["c"],
            "high",
            "CMake/Meson manifest with only C sources (tie-break 1).",
            signals,
        )
    if (manifests & SHELL_MANIFESTS) and not lang_counts.keys() - {"bash"}:
        return Verdict(
            "bash", AGENT["bash"], "high", "Shell markers only.", signals
        )

    # Tier 4: extension census. Dominant >70% wins, else the router.
    total = sum(lang_counts.values())
    if total == 0:
        return Verdict(
            "unknown",
            AGENT["router"],
            "low",
            "No recognizable source files; router decides.",
            signals,
        )
    top_lang, top_n = lang_counts.most_common(1)[0]
    share = top_n / total
    if share >= 0.70:
        return Verdict(
            top_lang,
            AGENT[top_lang],
            "medium",
            f"Census: {top_lang} is {share:.0%} of {total} source files (>=70%).",
            signals,
        )
    return Verdict(
        "mixed",
        AGENT["router"],
        "low",
        f"No language reaches 70% of {total} files (top {top_lang} {share:.0%}); "
        "router splits the work (tie-break 7).",
        signals,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="detect_language.py",
        description="Route a repo to a system-developer language agent.",
        epilog="Mirrors skills/_shared/language-detection.md (source of truth).",
    )
    parser.add_argument(
        "--path", default=".", help="directory to inspect (default: .)"
    )
    parser.add_argument(
        "--json", action="store_true", help="print the full verdict as JSON to stdout"
    )
    args = parser.parse_args(argv)

    root = Path(args.path).resolve()
    if not root.exists():
        print(f"error: path does not exist: {root}", file=sys.stderr)
        return 2

    verdict = detect(root)
    if args.json:
        print(json.dumps(asdict(verdict), indent=2))
    else:
        print(verdict.agent)
        print(
            f"language={verdict.language} confidence={verdict.confidence} "
            f"reason={verdict.reason}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
