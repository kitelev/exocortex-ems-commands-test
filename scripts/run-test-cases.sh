#!/usr/bin/env bash
# run-test-cases.sh — Homoiconic plugin testing diff oracle
#
# Phase 3 Task 3.1 of RFC aaaa2dea-abf3-4601-b800-286111b15ec2
#
# Procedure per Approved test case (test__PositiveCommandTest with
# test__TestCase_status = test__TestCaseStatusApproved):
#   1. Parse fixture YAML — extract _command, _target, _seed,
#      _frozenClock, _expected (+ optional _inputBinding[*])
#   2. Run: apply <command> <target> --seed --frozen-clock --vault . --yes
#      → produces actual output file under vault root
#   3. diff actual vs expected — exit 1 on any divergence
#
# Sanity gate: if 0 Approved test cases found, fail-fast (silent green prevention).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES_DIR="${REPO_ROOT}/fixtures"
CLI="${EXOCORTEX_CLI:-npx @kitelev/exocortex-cli}"

# ANSI colours (skip in non-tty)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; NC=''
fi

echo -e "${YELLOW}=== Homoiconic plugin testing — diff oracle ===${NC}"
echo "Repo root:  ${REPO_ROOT}"
echo "Fixtures:   ${FIXTURES_DIR}"
echo "CLI:        ${CLI}"
echo

# --- Locate Approved PositiveCommandTest fixtures ---
# Pattern: search fixtures/ for files with both
#   exo__Instance_class containing test__PositiveCommandTest UID (53816772)
#   test__TestCase_status pointing at test__TestCaseStatusApproved UID (58225fec)
APPROVED_UID="58225fec-f45e-4d8e-b351-e916fe7b2431"
POSITIVE_CLS_UID="53816772-9367-4f0a-810a-30104d9bba81"

APPROVED_TESTS=()
for f in "${FIXTURES_DIR}"/*.md; do
  [ -f "$f" ] || continue
  if grep -q "${APPROVED_UID}" "$f" 2>/dev/null && grep -q "${POSITIVE_CLS_UID}" "$f" 2>/dev/null; then
    APPROVED_TESTS+=("$f")
  fi
done

TOTAL="${#APPROVED_TESTS[@]}"
if [ "$TOTAL" -eq 0 ]; then
  echo -e "${RED}FAIL: 0 Approved test cases found. Sanity gate triggered.${NC}"
  echo "Hint: ensure ≥1 fixture has both:"
  echo "  exo__Instance_class includes [[${POSITIVE_CLS_UID}]] (test__PositiveCommandTest)"
  echo "  test__TestCase_status: [[${APPROVED_UID}]] (Approved)"
  exit 1
fi

echo "Found ${TOTAL} Approved test case(s)."
echo

# --- Run each test case ---
PASSED=0
FAILED=0
FAILED_NAMES=()

for tc_file in "${APPROVED_TESTS[@]}"; do
  tc_name="$(basename "$tc_file" .md)"
  echo -e "${YELLOW}--- Test case: ${tc_name} ---${NC}"

  # Extract fields via grep (YAML frontmatter)
  CMD=$(grep '^test__CommandTestCase_command:' "$tc_file" | sed -E 's/.*\[\[([0-9a-f-]+).*/\1/')
  TGT=$(grep '^test__CommandTestCase_target:' "$tc_file" | sed -E 's/.*\[\[([0-9a-f-]+).*/\1/')
  SEED=$(grep '^test__CommandTestCase_seed:' "$tc_file" | sed -E 's/.*: *"?([^"]*)"?.*/\1/')
  CLOCK=$(grep '^test__CommandTestCase_frozenClock:' "$tc_file" | sed -E 's/.*: *"?([^"]*)"?.*/\1/')
  # _expected may be multi-line YAML — extract first wikilink
  EXPECTED_UID=$(awk '
    /^test__CommandTestCase_expected:/ {flag=1; next}
    flag && /^  - / {gsub(/.*\[\[|\]\].*/, ""); print; exit}
    flag && /^[^ ]/ {flag=0}
  ' "$tc_file" | head -1)

  if [ -z "$CMD" ] || [ -z "$TGT" ] || [ -z "$SEED" ] || [ -z "$CLOCK" ] || [ -z "$EXPECTED_UID" ]; then
    echo -e "${RED}  Missing required fields:${NC}"
    echo "    CMD=$CMD TGT=$TGT SEED=$SEED CLOCK=$CLOCK EXPECTED=$EXPECTED_UID"
    FAILED=$((FAILED + 1)); FAILED_NAMES+=("$tc_name [parse error]")
    continue
  fi

  echo "  command:      ${CMD}"
  echo "  target:       ${TGT}"
  echo "  seed:         ${SEED}"
  echo "  frozen-clock: ${CLOCK}"
  echo "  expected:     ${EXPECTED_UID}"

  # Locate expected file (in fixtures/ for now; will move when CI matures)
  EXPECTED_FILE="${FIXTURES_DIR}/${EXPECTED_UID}.md"
  if [ ! -f "$EXPECTED_FILE" ]; then
    echo -e "${RED}  Expected fixture missing: $EXPECTED_FILE${NC}"
    FAILED=$((FAILED + 1)); FAILED_NAMES+=("$tc_name [missing expected]")
    continue
  fi

  # Run apply — output captured to tmpfile
  ACTUAL_TMP=$(mktemp -d "/tmp/exocortex-test-XXXXXX")
  trap "rm -rf '$ACTUAL_TMP'" EXIT

  if ! ${CLI} apply "$CMD" "$TGT" \
        --seed "$SEED" \
        --frozen-clock "$CLOCK" \
        --vault "$REPO_ROOT" \
        --yes \
        2>&1 | tee "$ACTUAL_TMP/apply.log" | tail -20; then
    echo -e "${RED}  apply CLI failed (see $ACTUAL_TMP/apply.log)${NC}"
    FAILED=$((FAILED + 1)); FAILED_NAMES+=("$tc_name [apply error]")
    continue
  fi

  # Locate actual output — apply writes to the grounding's targetFolder.
  # For pilot: 03 Knowledge/inbox/<seed-derived-uuid>.md inside vault.
  # We compute the expected-UID-derived path under vault root.
  ACTUAL_FILE=$(find "$REPO_ROOT" -name "${EXPECTED_UID}.md" -not -path "*/fixtures/*" -not -path "*/.git/*" 2>/dev/null | head -1)
  if [ -z "$ACTUAL_FILE" ]; then
    # Fall back: any .md created within last 30s in vault
    ACTUAL_FILE=$(find "$REPO_ROOT" -name "*.md" -newer "$ACTUAL_TMP/apply.log" -not -path "*/fixtures/*" -not -path "*/.git/*" 2>/dev/null | head -1)
  fi

  if [ -z "$ACTUAL_FILE" ] || [ ! -f "$ACTUAL_FILE" ]; then
    echo -e "${RED}  Actual output file not found (apply succeeded but no new file in vault)${NC}"
    FAILED=$((FAILED + 1)); FAILED_NAMES+=("$tc_name [no output]")
    continue
  fi

  echo "  actual:       ${ACTUAL_FILE}"

  if diff -u "$EXPECTED_FILE" "$ACTUAL_FILE"; then
    echo -e "${GREEN}  PASS${NC}"
    PASSED=$((PASSED + 1))
  else
    echo -e "${RED}  FAIL — diff above${NC}"
    FAILED=$((FAILED + 1)); FAILED_NAMES+=("$tc_name [diff mismatch]")
  fi

  # Cleanup actual output to allow re-runs
  rm -f "$ACTUAL_FILE" 2>/dev/null || true
  echo
done

# --- Summary ---
echo "=========================================="
echo "Total:  ${TOTAL}"
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"

if [ "$FAILED" -gt 0 ]; then
  echo
  echo "Failed test cases:"
  for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
  exit 1
fi

echo -e "${GREEN}All test cases passed.${NC}"
exit 0
