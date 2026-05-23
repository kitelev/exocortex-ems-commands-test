# `exocortex-ems-commands-test` — Acceptance test fixtures

Acceptance test repo for `ems-commands` ABox bindings (RFC `aaaa2dea`, Phase 2 Task 2.3).

## Structure

```
assetspaces/
├── ems              ← kitelev/exocortex-ems-ontology       (target class TBox)
├── ems-commands     ← kitelev/exocortex-ems-commands       (Command + Grounding + InheritanceRule under test)
├── test             ← kitelev/exocortex-test-ontology      (test__ namespace TBox)
├── exo              ← kitelev/exocortex-exo-ontology       (core types)
└── shared-identities ← kitelev/exocortex-shared-identities (Area UID + other shared)

fixtures/
├── <area-uid>.md                       (test input — ems__Area)
├── <expected-task-uid>.md              (test expected — ems__Task)
└── <test-case-uid>.md                  (test__PositiveCommandTest binding)
```

## Test methodology

```bash
# Clone with submodules
git clone --recurse-submodules kitelev/exocortex-ems-commands-test
cd exocortex-ems-commands-test
npm install   # pulls pinned @kitelev/exocortex-cli

# Run determinism test (homoiconic plugin testing — RFC aaaa2dea)
npx @kitelev/exocortex-cli apply bb00efed <area-uid> \
  --seed <test-case.test__CommandTestCase_seed> \
  --frozen-clock <test-case.test__CommandTestCase_frozenClock> \
  --vault . \
  > /tmp/actual.md

# Compare against expected (byte-for-byte)
diff /tmp/actual.md fixtures/<expected-task-uid>.md
# Exit code 0 → pass, !=0 → fail
```

## Conventions

- All fixture assets UUID-named (RFC-004 UUID-canon)
- Pinned CLI version via `package.json` — for reproducible CI runs
- Multi-submodule chain ensures: target class wikilinks resolve (ems), command/grounding under test resolves (ems-commands), test__ class definitions resolve (test), Area shared-id resolves (shared-identities)

## Phase 3 wiring (planned)

`scripts/run-test-cases.sh` will iterate all `test__PositiveCommandTest` instances in `fixtures/`, run `apply` with their `_seed`/`_frozenClock`, diff against `_expected`, accumulate pass/fail tally. GitHub Actions workflow exercises this on every push.
