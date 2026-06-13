# QA Stage Artifact Template (systems testing)

Primary artifact `.context/testing-N.md` is owned by igrsoft's qa-engineer; use this when sys-test-generator or a system-developer agent takes over QA or supplies the evidence body.

```markdown
---
handoff:
  stage: QA
  verdict: go           # go | no-go
  summary: "<test outcome — ≤200 chars>"
  files_touched:        # REQUIRED for QA (= tests added)
    - tests/parser_test.cpp
  key_decisions:        # REQUIRED for QA (= results)
    - id: q1
      summary: "<suite result — ≤160 chars, e.g. '128/128 pass; ASan+UBSan clean'>"
      anchor: testing-0.md#results
  open_questions: []
  refs:
    development: development-0.md#tests-added
---

# QA Testing — <worktask_id>

## results

| Suite | Command | Result | Transcript |
|-------|---------|--------|------------|
| unit (C++) | `ctest --test-dir build/default` | 128/128 pass | .context/logs/ctest-<worktask_id>.log |
| sanitized | `ctest --test-dir build/asan-ubsan` | pass, 0 reports | .context/logs/asan-<worktask_id>.log |
| python | `uv run pytest` | 54/54 pass | .context/logs/pytest-<worktask_id>.log |

Gate (both required for `go` — workflow-integration/SKILL.md § QA Gate):
- [ ] All tests pass (full suite, not only new tests)
- [ ] ASan+UBSan clean on changed components (TSan separately if concurrency changed; pure Python/Bash: tests + lint clean)

## coverage

| Component | Tool | Line % | Target |
|-----------|------|--------|--------|
| src/parser | llvm-cov / gcovr / coverage.py / kcov | <n>% | per _shared/testing-principles.md |

## regressions

- <failures vs. the pre-change baseline, with suspected cause and owner, or "None">

## verdict

<go | no-go — one-line justification; on no-go list blocking defects>

Blocking defects (no-go only — these become `metadata.gate_blockers[]` verbatim on DV re-dispatch):
- <self-contained, actionable string with file:line / failing test name>
```

## Notes

- Sanitizer evidence is part of the gate, not optional garnish: rebuild changed C/C++ targets with `-fsanitize=address,undefined` and re-run their tests; attach the transcript path.
- Every transcript path in `## results` must exist under `.context/logs/`.
- Test selection for focused re-runs: `ctest -R <regex>`, `pytest -k <expr>`, `bats -f <regex>`.
- Frontmatter budget: ≤200 tokens, ≤30 lines.
