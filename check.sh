#!/bin/bash
# The clean-code gate. Every change must pass it before it is committed.
#   ./check.sh            Swift style, web typecheck/format/tests, Briefing tests
#   ./check.sh --staged   only what is staged (the pre-commit hook runs this)
#   ./check.sh --app      everything above, plus build the app and run its unit tests (slow)
#
# Swift style rule: no file may have more swift-format warnings than Dayflow's original
# version of it (new Dayframe files: zero). Upstream's own warnings are left alone so
# Dayframe stays easy to compare with Dayflow. Format a file with:
#   xcrun swift-format format -i <file>
set -uo pipefail
cd "$(dirname "$0")"

UPSTREAM=1df9be4 # the untouched Dayflow v2.6.0 import
MODE=${1:-all}
failed=()

section() { printf '\n== %s\n' "$1"; }
fail() {
  failed+=("$1")
  echo "FAIL: $1"
}

# Files to check: staged ones in --staged mode, all tracked ones otherwise.
files() {
  if [[ $MODE == --staged ]]; then
    git diff --cached --name-only --diff-filter=ACMR -- "$@"
  else
    git ls-files -- "$@"
  fi
}

# File contents to check: the staged blob in --staged mode, the working copy otherwise.
contents() {
  if [[ $MODE == --staged ]]; then git show ":$1"; else cat "$1"; fi
}

swift_warnings() {
  xcrun swift-format lint --configuration .swift-format --assume-filename "$1" 2>&1 >/dev/null | grep -c warning
}

upstream_warnings() {
  local old=${1/#App\//Dayflow/}
  if git cat-file -e "$UPSTREAM:$old" 2>/dev/null; then
    git show "$UPSTREAM:$old" | swift_warnings "$1"
  else
    echo 0
  fi
}

check_changelog() {
  section "Change log"
  if [[ $MODE == --staged ]] && ! git diff --cached --name-only | grep -qx CHANGELOG.md; then
    fail "CHANGELOG.md is not staged. Add an entry (### HH:MM: title, What/Files/Why/Checked)."
    return
  fi
  local log today top entry
  log=$(contents CHANGELOG.md)
  today=$(date +%F)
  top=$(grep -m1 '^## [0-9]' <<<"$log")
  # The newest entry: the first "### " under the first dated "## " heading (the template
  # at the top of the file sits inside a code block, above any dated heading).
  entry=$(awk '/^## [0-9]/{dated=1} dated && /^### /{n++} n==1' <<<"$log")
  [[ $top == "## $today"* ]] || fail "The newest day in CHANGELOG.md is '$top', expected '## $today'."
  for field in What Files Why Checked; do
    grep -q "^- \*\*$field:\*\*" <<<"$entry" || fail "The newest CHANGELOG entry has no **$field:** line."
  done
  echo "Newest entry: $(head -1 <<<"$entry")"
}

check_swift() {
  section "Swift style (swift-format)"
  local count=0 file now before
  while IFS= read -r file; do
    [[ -n $file ]] || continue
    count=$((count + 1))
    now=$(contents "$file" | swift_warnings "$file")
    ((now == 0)) && continue
    before=$(upstream_warnings "$file")
    if ((now > before)); then
      fail "$file has $now swift-format warnings (Dayflow's version had $before)."
      contents "$file" | xcrun swift-format lint --configuration .swift-format --assume-filename "$file" 2>&1 >/dev/null |
        head -5 | sed 's/^/    /'
    fi
  done < <(files 'App/*.swift')
  echo "$count Swift file(s) checked."
}

check_web() {
  section "Web (typecheck, format, tests)"
  local web
  web=$(files 'Web/*.ts' 'Web/*.tsx' 'Web/*.css' 'Web/*.html' 'Web/package.json')
  if [[ -z $web ]]; then
    echo "No web changes."
    return
  fi
  [[ -d Web/node_modules ]] || npm --prefix Web ci --no-audit --no-fund >/dev/null 2>&1
  npm --prefix Web run --silent typecheck || fail "Web typecheck"
  local formatted
  formatted=$(grep -E '^Web/src/.*\.(ts|tsx|css)$|^Web/[^/]*\.ts$' <<<"$web" | sed 's#^Web/##')
  if [[ -n $formatted ]]; then
    (cd Web && xargs npx --no-install prettier --check --log-level warn <<<"$formatted") ||
      fail "Web formatting (run: npm --prefix Web run format)"
  fi
  npm --prefix Web run --silent test || fail "Web tests"
}

check_briefing() {
  section "Briefing tests"
  if [[ -z $(files 'Briefing/*.py' 'Briefing/tests/*') ]]; then
    echo "No Briefing changes."
    return
  fi
  local out
  out=$(cd Briefing && python3 -m unittest discover -s tests 2>&1)
  grep -E '^Ran [0-9]+ tests' <<<"$out"
  if ! grep -q '^OK' <<<"$out"; then
    grep -E '^(FAIL|ERROR): ' <<<"$out" | sed 's/^/    /'
    fail "Briefing tests"
  fi
}

check_app() {
  section "App build + unit tests (slow)"
  local free
  free=$(df -g "$HOME" | awk 'NR==2{print $4}')
  if ((free < 3)); then
    fail "Only ${free} GB free; the app build needs about 3 GB."
    return
  fi
  mkdir -p build
  if xcodebuild test -project App/Dayflow.xcodeproj -scheme Dayflow -configuration Debug \
    -derivedDataPath build -destination 'platform=macOS' -only-testing:DayflowTests \
    -parallel-testing-enabled NO -skipPackagePluginValidation -skipMacroValidation \
    >build/last-test.log 2>&1; then
    grep -E 'Executed [0-9]+ tests' build/last-test.log | tail -1
  else
    grep -E ': error: |error: -\[|failed \(' build/last-test.log | head -20
    fail "App build/tests (full log: build/last-test.log)"
  fi
}

check_changelog
check_swift
check_web
check_briefing
[[ $MODE == --app ]] && check_app

echo
if ((${#failed[@]})); then
  echo "check.sh: ${#failed[@]} problem(s). Fix them before committing."
  exit 1
fi
echo "check.sh: all clean."
