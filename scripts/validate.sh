#!/usr/bin/env bash
#
# validate.sh — release-gate validator for the system-developer plugin.
#
# Verifies that the two manifests, agents, commands, and skills form a
# self-consistent, installable plugin before release. Findings print as:
#
#   SEVERITY path message | fix: hint
#
# SEVERITY is one of ERROR or WARN. With --strict, WARN findings also cause
# a non-zero exit (CI gate). Without --strict, only ERROR findings fail.
#
# Usage:
#   scripts/validate.sh [--strict]
#
# Exit codes:
#   0  no findings (or only warnings without --strict)
#   1  at least one ERROR (always), or any WARN under --strict
#   2  usage / environment error (e.g. jq missing)
#
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

STRICT=0
for arg in "$@"; do
	case "$arg" in
		--strict) STRICT=1 ;;
		-h | --help)
			grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
			exit 0
			;;
		*)
			printf 'ERROR %s unknown argument "%s" | fix: run with --strict or no args\n' "$0" "$arg" >&2
			exit 2
			;;
	esac
done

# Resolve repo root as the parent of this script's directory, so the script
# works regardless of the caller's working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

ERR_COUNT=0
WARN_COUNT=0

err() {
	# err <path> <message> <fix-hint>
	printf 'ERROR %s %s | fix: %s\n' "$1" "$2" "$3"
	ERR_COUNT=$((ERR_COUNT + 1))
}

warn() {
	# warn <path> <message> <fix-hint>
	printf 'WARN %s %s | fix: %s\n' "$1" "$2" "$3"
	WARN_COUNT=$((WARN_COUNT + 1))
}

need() {
	command -v "$1" >/dev/null 2>&1 || {
		printf 'ERROR %s required tool "%s" not found | fix: install %s and re-run\n' "$0" "$1" "$1" >&2
		exit 2
	}
}

need jq

PLUGIN_MANIFEST=".claude-plugin/plugin.json"
MARKET_MANIFEST=".claude-plugin/marketplace.json"

# Frontmatter helper: extract a scalar field's value from a markdown file's
# YAML frontmatter (first --- ... --- block). Prints empty string if absent.
# Handles "key: value" and "key: >-"/"key: |" block scalars (folded onto one
# line for presence checks). Strips surrounding quotes.
fm_field() {
	# fm_field <file> <key>
	awk -v key="$2" '
		BEGIN { infm = 0; depth = 0 }
		NR == 1 && $0 == "---" { infm = 1; next }
		infm && $0 == "---" { exit }
		infm {
			# match "key:" at column 0 (no leading space)
			if ($0 ~ "^" key ":[ \t]*") {
				val = $0
				sub("^" key ":[ \t]*", "", val)
				# block scalar indicators -> read following indented lines
				if (val == ">-" || val == ">" || val == "|" || val == "|-") {
					getline nextline
					gsub(/^[ \t]+/, "", nextline)
					print nextline
					exit
				}
				gsub(/^["'\'']|["'\'']$/, "", val)
				print val
				exit
			}
		}
	' "$1"
}

# Collect the full frontmatter description (may span multiple lines for block
# scalars). Used for trigger-phrase lint.
fm_description_full() {
	awk '
		BEGIN { infm = 0; capture = 0 }
		NR == 1 && $0 == "---" { infm = 1; next }
		infm && $0 == "---" { exit }
		infm {
			if (capture) {
				# stop at next top-level key (non-indented "key:")
				if ($0 ~ /^[A-Za-z0-9_-]+:/) { exit }
				line = $0; gsub(/^[ \t]+/, "", line); printf "%s ", line
				next
			}
			if ($0 ~ /^description:[ \t]*/) {
				val = $0; sub(/^description:[ \t]*/, "", val)
				if (val == ">-" || val == ">" || val == "|" || val == "|-") { capture = 1; next }
				gsub(/^["'\'']|["'\'']$/, "", val); printf "%s", val; exit
			}
		}
	' "$1"
}

# ---------------------------------------------------------------------------
# 1. Manifests exist and parse
# ---------------------------------------------------------------------------

for m in "${PLUGIN_MANIFEST}" "${MARKET_MANIFEST}"; do
	if [[ ! -f "${m}" ]]; then
		err "${m}" "manifest missing" "create ${m} per plan §5"
		continue
	fi
	if ! jq empty "${m}" >/dev/null 2>&1; then
		err "${m}" "invalid JSON (jq parse failed)" "validate JSON with: jq . ${m}"
	fi
done

# ---------------------------------------------------------------------------
# 2. Marketplace manifest path references exist
# ---------------------------------------------------------------------------

# Build newline-delimited lists of declared agents/commands/skills (relative
# paths) from the marketplace manifest's first plugin entry. Newline-delimited
# strings (rather than associative arrays) keep this script portable to the
# bash 3.2 shipped with macOS.
DECLARED_AGENTS=""
DECLARED_COMMANDS=""
DECLARED_SKILLS=""

if [[ -f "${MARKET_MANIFEST}" ]] && jq empty "${MARKET_MANIFEST}" >/dev/null 2>&1; then
	DECLARED_AGENTS="$(jq -r '.plugins[0].agents[]? // empty' "${MARKET_MANIFEST}")"
	DECLARED_COMMANDS="$(jq -r '.plugins[0].commands[]? // empty' "${MARKET_MANIFEST}")"
	DECLARED_SKILLS="$(jq -r '.plugins[0].skills[]? // empty' "${MARKET_MANIFEST}")"

	# Every declared agent/command path must exist as a file.
	while IFS= read -r p; do
		[[ -z "${p}" ]] && continue
		[[ -f "${p#./}" ]] || err "${MARKET_MANIFEST}" "agents[] entry '${p}' does not exist" "create the file or remove it from agents[]"
	done <<<"${DECLARED_AGENTS}"
	while IFS= read -r p; do
		[[ -z "${p}" ]] && continue
		[[ -f "${p#./}" ]] || err "${MARKET_MANIFEST}" "commands[] entry '${p}' does not exist" "create the file or remove it from commands[]"
	done <<<"${DECLARED_COMMANDS}"
	# Every declared skill path must be a directory containing SKILL.md,
	# except the bare "./skills" root which is a namespace marker.
	while IFS= read -r p; do
		[[ -z "${p}" ]] && continue
		rel="${p#./}"
		if [[ ! -d "${rel}" ]]; then
			err "${MARKET_MANIFEST}" "skills[] entry '${p}' is not a directory" "create the directory or remove it from skills[]"
			continue
		fi
		# The skills root namespace entry need not hold SKILL.md directly.
		[[ "${rel}" == "skills" ]] && continue
		[[ -f "${rel}/SKILL.md" ]] || err "${MARKET_MANIFEST}" "skills[] entry '${p}' has no SKILL.md" "add ${rel}/SKILL.md or remove the entry"
	done <<<"${DECLARED_SKILLS}"
fi

# Plugin manifest hook script references must exist (if any are declared).
if [[ -f "${PLUGIN_MANIFEST}" ]] && jq empty "${PLUGIN_MANIFEST}" >/dev/null 2>&1; then
	while IFS= read -r hookcmd; do
		[[ -z "${hookcmd}" ]] && continue
		# Extract a path token that looks like a hooks/ script.
		hookpath="$(printf '%s\n' "${hookcmd}" | grep -oE '[^ ]*hooks/[A-Za-z0-9._/-]+\.sh' | head -1 || true)"
		[[ -z "${hookpath}" ]] && continue
		# Normalize ${CLAUDE_PLUGIN_ROOT}/ prefix to repo-relative.
		hookpath="${hookpath#\$\{CLAUDE_PLUGIN_ROOT\}/}"
		hookpath="${hookpath#./}"
		[[ -f "${hookpath}" ]] || err "${PLUGIN_MANIFEST}" "hook script '${hookpath}' not found" "create the script or fix the hooks wiring"
	done < <(jq -r '.hooks // {} | .. | .command? // empty' "${PLUGIN_MANIFEST}" 2>/dev/null || true)
fi

# ---------------------------------------------------------------------------
# 3. Orphan detection: agents/ and commands/ files missing from the manifest
# ---------------------------------------------------------------------------

# Helper: is a repo-relative path present in a newline-delimited declared list?
# Compares each list entry both as-is and with a leading "./" stripped.
in_list() {
	# in_list <needle-rel> <newline-delimited-list>
	local needle="$1" list="$2" item
	while IFS= read -r item; do
		[[ -z "${item}" ]] && continue
		[[ "${item#./}" == "${needle}" ]] && return 0
	done <<<"${list}"
	return 1
}

if [[ -d agents ]]; then
	while IFS= read -r f; do
		rel="${f#./}"
		# _base/ is intentionally excluded from the manifest.
		[[ "${rel}" == agents/_base/* ]] && continue
		in_list "${rel}" "${DECLARED_AGENTS}" \
			|| err "${rel}" "agent file not listed in marketplace agents[]" "add \"./${rel}\" to agents[] or move it under agents/_base/"
	done < <(find agents -type f -name '*.md')
fi

if [[ -d commands ]]; then
	while IFS= read -r f; do
		rel="${f#./}"
		in_list "${rel}" "${DECLARED_COMMANDS}" \
			|| err "${rel}" "command file not listed in marketplace commands[]" "add \"./${rel}\" to commands[]"
	done < <(find commands -type f -name '*.md')
fi

# ---------------------------------------------------------------------------
# 4. Command frontmatter: description, argument-hint, allowed-tools
# ---------------------------------------------------------------------------

TOOL_WHITELIST=" Read Write Edit Glob Grep Bash WebSearch WebFetch "

if [[ -d commands ]]; then
	while IFS= read -r f; do
		rel="${f#./}"
		desc="$(fm_field "${f}" description)"
		hint="$(fm_field "${f}" "argument-hint")"
		tools="$(fm_field "${f}" "allowed-tools")"

		[[ -n "${desc}" ]] || err "${rel}" "frontmatter missing 'description'" "add a description: line to the frontmatter"
		[[ -n "${hint}" ]] || err "${rel}" "frontmatter missing 'argument-hint'" "add an argument-hint: line to the frontmatter"
		if [[ -z "${tools}" ]]; then
			err "${rel}" "frontmatter missing 'allowed-tools'" "add an allowed-tools: line to the frontmatter"
		else
			# Validate each comma-separated entry against the whitelist. An
			# entry may be a bare tool name or a scoped form (e.g. Bash(git:*));
			# the base name before "(" is what we whitelist.
			IFS=',' read -ra entries <<<"${tools}"
			for entry in "${entries[@]}"; do
				base="$(printf '%s' "${entry}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/\(.*$//')"
				[[ -z "${base}" ]] && continue
				if [[ "${TOOL_WHITELIST}" != *" ${base} "* ]]; then
					err "${rel}" "allowed-tools entry '${base}' not in whitelist" "use only: Read, Write, Edit, Glob, Grep, Bash, WebSearch, WebFetch"
				fi
			done
		fi
		# Note: slash-command descriptions are imperative summaries; the
		# "Use when" / "Use PROACTIVELY" trigger lint applies only to
		# auto-invoked agents and skills (see sections 5 and 6).
	done < <(find commands -type f -name '*.md')
fi

# ---------------------------------------------------------------------------
# 5. Skills: SKILL.md frontmatter + size/references heuristic + path links
# ---------------------------------------------------------------------------

if [[ -d skills ]]; then
	while IFS= read -r skill; do
		dir="$(dirname "${skill}")"
		rel="${skill#./}"
		sname="$(fm_field "${skill}" name)"
		sdesc="$(fm_field "${skill}" description)"
		[[ -n "${sname}" ]] || err "${rel}" "SKILL.md frontmatter missing 'name'" "add a name: field to the frontmatter"
		[[ -n "${sdesc}" ]] || err "${rel}" "SKILL.md frontmatter missing 'description'" "add a description: field to the frontmatter"

		# Trigger-phrase lint.
		fulldesc="$(fm_description_full "${skill}")"
		if [[ "${fulldesc}" != *"Use when"* && "${fulldesc}" != *"Use PROACTIVELY"* ]]; then
			warn "${rel}" "description lacks a 'Use when' / 'Use PROACTIVELY' trigger phrase" "add an explicit invocation trigger to the description"
		fi

		# Body > 8KB without a references/ sibling -> warning. Measure body
		# size by subtracting the frontmatter is overkill; the 8KB rule is a
		# heuristic, so use total file size.
		bytes="$(wc -c <"${skill}" | tr -d '[:space:]')"
		if [[ "${bytes}" -gt 8192 && ! -d "${dir}/references" ]]; then
			warn "${rel}" "SKILL.md is ${bytes} bytes (>8KB) with no references/ sibling" "split detail into a references/ directory beside SKILL.md"
		fi
	done < <(find skills -type f -name 'SKILL.md')

	# Backticked references/ and templates/ paths mentioned in skills files
	# must resolve. A backticked path may be written relative to the file's
	# own directory, relative to the skills/ root, or relative to the repo
	# root; accept any of those.
	while IFS= read -r f; do
		rel="${f#./}"
		fdir="$(dirname "${f}")"
		# Extract backticked tokens containing references/, templates/, or scripts/.
		# shellcheck disable=SC2016 # backticks are literal markdown delimiters here
		refs="$(grep -oE '`[^`]*(references|templates|scripts)/[A-Za-z0-9._/-]+`' "${f}" 2>/dev/null | tr -d '`' | sort -u || true)"
		while IFS= read -r ref; do
			[[ -z "${ref}" ]] && continue
			# ${CLAUDE_SKILL_DIR} is the installed skills root; normalize it to
			# the repo-relative skills/ so the resolutions below can match.
			ref="${ref#\$\{CLAUDE_SKILL_DIR\}/}"
			# A backticked path may be relative to the file's own directory,
			# the repo root, or the skills/ root; accept any resolution.
			if [[ -e "${fdir}/${ref}" ]] || [[ -e "${ref}" ]] || [[ -e "skills/${ref}" ]]; then
				continue
			fi
			warn "${rel}" "references a path '${ref}' that does not exist" "create the referenced file or fix the link"
		done <<<"${refs}"
	done < <(find skills -type f -name '*.md')
fi

# ---------------------------------------------------------------------------
# 6. Agent frontmatter: name/description/model + uniqueness + collisions
# ---------------------------------------------------------------------------

# Gather external agent names to check collisions against. Exclude this
# plugin's own cache copies (anything under a system-developer path) so a
# previously-installed build does not collide with itself. The result is a
# newline-delimited "name<TAB>path" table (bash 3.2 has no associative arrays).
EXTERNAL_NAMES=""

collect_external() {
	# collect_external <glob-expanded-file>; appends to EXTERNAL_NAMES.
	local file="$1" n
	[[ -f "${file}" ]] || return 0
	# Skip our own plugin's cached agents.
	case "${file}" in
		*/system-developer/*) return 0 ;;
	esac
	n="$(fm_field "${file}" name)"
	[[ -n "${n}" ]] && EXTERNAL_NAMES="${EXTERNAL_NAMES}${n}	${file}"$'\n'
}

shopt -s nullglob
for f in "${HOME}"/.claude/plugins/cache/*/*/*/agents/*.md; do
	collect_external "${f}"
done
if [[ -n "${COMPANY_WORKFLOW_DIR:-}" && -d "${COMPANY_WORKFLOW_DIR}/agents" ]]; then
	for f in "${COMPANY_WORKFLOW_DIR}/agents"/*.md; do
		collect_external "${f}"
	done
fi
shopt -u nullglob

# Walk this plugin's agents, checking completeness, in-repo uniqueness, and
# external collisions. SEEN_NAMES is a newline-delimited "name<TAB>path" table.
SEEN_NAMES=""

if [[ -d agents ]]; then
	while IFS= read -r f; do
		rel="${f#./}"
		# _base agents are shared templates (no YAML frontmatter, mirroring
		# apple-developer's platform-agent.md); skip all frontmatter checks.
		if [[ "${rel}" == agents/_base/* ]]; then
			continue
		fi

		aname="$(fm_field "${f}" name)"
		adesc="$(fm_field "${f}" description)"
		amodel="$(fm_field "${f}" model)"

		[[ -n "${aname}" ]] || err "${rel}" "frontmatter missing 'name'" "add a name: field"
		[[ -n "${adesc}" ]] || err "${rel}" "frontmatter missing 'description'" "add a description: field"
		[[ -n "${amodel}" ]] || err "${rel}" "frontmatter missing 'model'" "add a model: field (opus/sonnet/haiku)"

		# Trigger-phrase lint: agent descriptions should declare auto-invocation.
		afulldesc="$(fm_description_full "${f}")"
		if [[ "${afulldesc}" != *"Use when"* && "${afulldesc}" != *"Use PROACTIVELY"* ]]; then
			warn "${rel}" "description lacks a 'Use when' / 'Use PROACTIVELY' trigger phrase" "add an explicit invocation trigger to the description"
		fi

		[[ -z "${aname}" ]] && continue

		# In-repo uniqueness (exact match on the tab-delimited name field).
		prior="$(printf '%s' "${SEEN_NAMES}" | awk -F'\t' -v n="${aname}" '$1 == n {print $2; exit}')"
		if [[ -n "${prior}" ]]; then
			err "${rel}" "agent name '${aname}' duplicated (also in ${prior})" "rename one of the agents so names are unique"
		else
			SEEN_NAMES="${SEEN_NAMES}${aname}	${rel}"$'\n'
		fi

		# External collision against installed plugins + company-workflow.
		ext="$(printf '%s' "${EXTERNAL_NAMES}" | awk -F'\t' -v n="${aname}" '$1 == n {print $2; exit}')"
		[[ -n "${ext}" ]] && err "${rel}" "agent name '${aname}' collides with ${ext}" "rename to a sys-prefixed or otherwise unique name"
	done < <(find agents -type f -name '*.md')
fi

# ---------------------------------------------------------------------------
# 7. subagent_type references in commands/ and agents/
# ---------------------------------------------------------------------------

# Allowed plugin prefixes for subagent_type values.
ALLOWED_PREFIX_RE='^(system-developer|company-workflow|security-scanning|debugging-toolkit|general-purpose)'

check_subagent_refs() {
	# check_subagent_refs <dir>
	local d="$1" f rel
	[[ -d "${d}" ]] || return 0
	while IFS= read -r f; do
		rel="${f#./}"
		local refs
		refs="$(grep -oE 'subagent_type="[^"]*"' "${f}" 2>/dev/null | sed -E 's/^subagent_type="//; s/"$//' | sort -u || true)"
		while IFS= read -r st; do
			[[ -z "${st}" ]] && continue
			# Documentation placeholders use angle brackets; skip them.
			case "${st}" in
				*"<"* | *">"*) continue ;;
			esac
			# Prefix whitelist.
			if [[ ! "${st}" =~ ${ALLOWED_PREFIX_RE} ]]; then
				err "${rel}" "subagent_type '${st}' has a disallowed plugin prefix" "use system-developer:/company-workflow:/security-scanning:/debugging-toolkit:/general-purpose:"
				continue
			fi
			# Own-plugin targets must exist as agent files.
			case "${st}" in
				system-developer:*)
					target="${st#system-developer:}"
					if [[ ! -f "agents/${target}.md" ]]; then
						err "${rel}" "subagent_type '${st}' targets a missing own-plugin agent" "create agents/${target}.md or fix the reference"
					fi
					;;
			esac
		done <<<"${refs}"
	done < <(find "${d}" -type f -name '*.md')
}

check_subagent_refs commands
check_subagent_refs agents

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n'
printf 'Summary: %d error(s), %d warning(s)%s\n' "${ERR_COUNT}" "${WARN_COUNT}" \
	"$(if [[ "${STRICT}" -eq 1 ]]; then printf ' (strict)'; fi)"

if [[ "${ERR_COUNT}" -gt 0 ]]; then
	exit 1
fi
if [[ "${STRICT}" -eq 1 && "${WARN_COUNT}" -gt 0 ]]; then
	exit 1
fi
exit 0
