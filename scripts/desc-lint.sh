#!/usr/bin/env bash
#
# desc-lint.sh — frontmatter description-length lint (two-tier caps).
#
# Frontmatter descriptions are AMBIENT: Claude Code injects them into every
# session's startup context in every project with the plugin enabled.
# Multi-line YAML scalars (`description: |` / `>`) hide overruns from
# single-line greps — this lint joins continuation lines before measuring.
#
# Two tiers, chosen by path:
#   agents/**, commands/**  → 250  — CC guidance caps ambient agent/command
#                                     descriptions at ~250 chars (current
#                                     maxima sit at 240, so the tier is green).
#   skills/**/SKILL.md      → 600  — skill descriptions are deliberately
#                                     trigger-engineered (they must fire the
#                                     right skill), so 600 is a regression
#                                     brake set just above today's worst
#                                     (embedded-cpp), NOT a target. It is a
#                                     diet pending measured trigger evals — do
#                                     not tighten without eval evidence that a
#                                     shorter description still fires reliably.
#
# Usage:
#   scripts/desc-lint.sh              # lint agents/**, commands/**, skills/**/SKILL.md
#   scripts/desc-lint.sh <file> [...] # lint specific files
#   scripts/desc-lint.sh --self-test  # verify the parser against inline fixtures
#
# Exit codes: 0 = all within cap, 1 = at least one over cap, 2 = usage/parser error.
#
# CI / repo-maintenance helper only — never read by agents at runtime.
#
set -Eeuo pipefail

lint() {
	python3 - "$@" <<'PYEOF'
import re, sys

def cap_for(path):
    # Segment-anchored so both repo-relative (skills/..) and self-test
    # temp paths (/tmp/x/skills/..) classify identically.
    if re.search(r'(^|/)skills/', path):
        return 600
    return 250  # agents/, commands/, and any unclassified path

def desc_len(path):
    try:
        t = open(path, encoding='utf-8').read()
    except OSError as e:
        print(f"desc-lint: cannot read {path}: {e}", file=sys.stderr)
        return None
    m = re.match(r'^---\r?\n(.*?)\r?\n---', t, re.S)
    if not m:
        return None  # no frontmatter — nothing to lint
    out, cap = [], False
    for ln in m.group(1).split('\n'):
        if re.match(r'^description:', ln):
            cap = True
            v = ln.split(':', 1)[1].strip()
            if v and v not in ('|', '>', '|-', '>-'):
                out.append(v)
            continue
        if cap:
            if re.match(r'^\S', ln):
                break  # next top-level key
            out.append(ln.strip())
    return len(' '.join(' '.join(out).split())) if out else 0

fail = 0
for path in sys.argv[1:]:
    n = desc_len(path)
    if n is None:
        continue
    cap = cap_for(path)
    if n > cap:
        fail = 1
        print(f"desc-lint: {path}: {n} chars (cap {cap}) — OVER")
    else:
        print(f"desc-lint: {path}: {n} chars (cap {cap}) ok")
sys.exit(fail)
PYEOF
}

self_test() {
	td=$(mktemp -d -t desc-lint-XXXXXX)
	trap 'rm -rf "${td}"' EXIT
	mkdir -p "${td}/skills"
	# fixture 1: single-line, within the 250 tier
	printf -- '---\nname: a\ndescription: short and sweet\nmodel: sonnet\n---\nbody\n' >"${td}/ok.md"
	# fixture 2: multi-line block scalar, over the 250 tier
	long=$(printf 'x%.0s' {1..130})
	printf -- '---\nname: b\ndescription: |\n  %s\n  %s\nmodel: sonnet\n---\nbody\n' "${long}" "${long}" >"${td}/over.md"
	# fixture 3: no frontmatter
	printf -- '# plain markdown\n' >"${td}/plain.md"
	# fixture 4: skills tier — >250 (would fail agent tier) but <600, must pass
	mid=$(printf 's%.0s' {1..400})
	printf -- '---\nname: s1\ndescription: %s\n---\nbody\n' "${mid}" >"${td}/skills/mid.md"
	# fixture 5: skills tier — over 600, must fail
	huge=$(printf 'h%.0s' {1..700})
	printf -- '---\nname: s2\ndescription: %s\n---\nbody\n' "${huge}" >"${td}/skills/huge.md"

	if ! lint "${td}/ok.md" "${td}/plain.md" "${td}/skills/mid.md" >/dev/null; then
		echo "desc-lint self-test: FAIL (within-cap fixtures flagged)" >&2; exit 2
	fi
	if lint "${td}/over.md" >/dev/null; then
		echo "desc-lint self-test: FAIL (agent-tier over fixture passed)" >&2; exit 2
	fi
	if lint "${td}/skills/huge.md" >/dev/null; then
		echo "desc-lint self-test: FAIL (skills-tier over fixture passed)" >&2; exit 2
	fi
	echo "desc-lint self-test: ALL PASS"
}

repo_files() {
	git ls-files -- 'agents/*.md' 'agents/_base/*.md' 'commands/*.md' \
		'skills/SKILL.md' 'skills/**/SKILL.md' \
		| sort -u
}

case "${1:-}" in
	--self-test) self_test ;;
	"")
		cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
		# shellcheck disable=SC2046 # repo_files emits one clean path per line
		lint $(repo_files) | { grep -v ' ok$' || true; }
		;;
	*) lint "$@" ;;
esac
