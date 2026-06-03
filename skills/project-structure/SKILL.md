---
name: project-structure
description: The standard for how a repo is laid out and how files/modules are named, so every project looks the same and generated code has an obvious right place. Use when creating a new file, module, or directory, deciding where something goes, naming a file/folder, scaffolding a new repo, or reviewing whether code is well-organized. Counters the AI-slop failure mode of sprawling, inconsistently-placed, god-everything files. Litmus: a new thing has exactly one obvious home, and any repo is navigable on sight.
---

# Project structure

Advisory standard — fires on the situation in the description, no command to invoke. The judgment-layer counterpart to the mechanical guardrails: linters catch dead code and complexity; this catches *placement and organization*, the part tools can't judge.

## The rule

Every repo follows the same shape, so any project is navigable on sight and generated code has one obvious home. Three principles, in priority order:

1. **Consistency across repos beats local cleverness.** A developer (or agent) dropped into any of your projects should find things in the same places. Don't invent a new layout per repo.
2. **Colocate by feature, not by type.** Group code by what it does (`auth/`, `billing/`), not by technical kind (`controllers/`, `services/`, `utils/` at the top level). A feature's code, tests, and types live together.
3. **One module, one responsibility.** A file that needs "and" to describe it is two files. New behavior gets a new well-named module, not another 50 lines bolted onto a god-file.

## Reference layouts

These are the baseline. Adapt the names to the project, not the shape.

**Python**
```
repo/
├── src/<package>/          # the package; feature subpackages inside
│   ├── <feature>/          # colocated: logic + its types
│   └── __init__.py
├── tests/                  # mirrors src/ layout
├── pyproject.toml          # deps + ruff + mypy config (single source)
├── justfile                # the check recipes (verify/fix) — shared by hooks + CI
├── lefthook.yml            # git-hook dispatcher
├── .github/workflows/      # (or bitbucket-pipelines.yml — same recipes)
├── docs/
├── README.md
└── CLAUDE.md               # project conventions for agents
```

**TS / Node**
```
repo/
├── src/
│   └── <feature>/          # feature.ts + feature.test.ts + feature.types.ts together
├── package.json            # deps + scripts (lint, typecheck, test, format:check)
├── tsconfig.json
├── eslint config + prettier config
├── justfile                # the check recipes (verify/fix) — shared by hooks + CI
├── lefthook.yml            # git-hook dispatcher
├── .github/workflows/      # (or bitbucket-pipelines.yml — same recipes)
├── docs/
├── README.md
└── CLAUDE.md
```

**Rust**
```
repo/
├── src/                    # or crates/<name>/src/ for a workspace
│   └── <feature>/          # mod.rs + colocated tests (#[cfg(test)]) + types
├── Cargo.toml              # deps; clippy + rustfmt config
├── justfile                # the check recipes — shared by hooks + CI
├── lefthook.yml
├── .github/workflows/
├── docs/
├── README.md
└── CLAUDE.md
```

Monorepos: one `packages/<name>/` (or `crates/<name>/`) per package, each following the above internally.

## Naming conventions

- **Directories & files:** match the ecosystem's norm and be consistent — `snake_case.py` for Python, `kebab-case.ts` or `camelCase.ts` for TS (pick one per repo and hold it), `snake_case.rs` for Rust. Test files sit next to their subject (`foo.test.ts`) or mirror in `tests/`.
- **No junk-drawer names.** `utils`, `helpers`, `misc`, `common`, `stuff` are smells — they accrete unrelated code. Name by what lives there (`formatting.ts`, `date.ts`). A shared module is fine when it has a real, nameable responsibility.
- **One public thing per file, named for the file.** `parse_manifest.py` exports `parse_manifest`; don't bury it in `helpers.py`.

## Why

This is an anti-slop guardrail that linters can't enforce. AI-generated code defaults to sprawl: a new endpoint becomes another branch in a 600-line `routes.ts`; a helper lands in `utils.ts` next to ten unrelated helpers; the same project gets a different layout every time. The cost shows up later — nobody can find anything, every file does five things, and review can't tell what changed.

A fixed structure removes the decision: there's one right place for the new thing, so generated code lands there instead of wherever the model felt like. And uniform repos mean the skills, hooks, and CI in this collection (which assume `src/`, `justfile`, `lefthook.yml`, a `.github/workflows/` or `bitbucket-pipelines.yml`) work everywhere without per-repo fiddling.

## How to apply

### When creating a new file or module
Ask: does this responsibility already have a home? If yes, extend it. If no, make a new well-named module in the right feature directory — never widen a god-file or drop it in `utils`.

### When scaffolding a new repo
Lay down the reference structure first (`src/`, `tests/`, `docs/`, `.github/` or `bitbucket-pipelines.yml`, `.claude/`, `README.md`, `CLAUDE.md`). The `quality-stack-setup` skill installs the tooling into this shape.

### When reviewing
Flag: top-level type-folders (`controllers/`/`services/`) instead of feature colocation; `utils`/`misc` junk drawers; files that do unrelated things; a layout that doesn't match the org's other repos. (Complexity and dead-code within a file are caught mechanically by a static-analysis scanner — this skill is about *placement and organization*, the part tools can't judge.)

## Litmus

A new feature, helper, or type has exactly one obvious place to live, and a stranger can navigate the repo on sight because it looks like every other repo you own.

## Related

- `quality-stack-setup` — installs the lint/type/test/scan tooling into this structure.
- a static-analysis scanner (e.g. skylos for Python, fallow for TS/JS, clippy for Rust) — catches the mechanical side (dead code, complexity, clones) that pairs with good structure.
