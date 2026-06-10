#!/bin/zsh
# terminal-tutor test suite. Run: zsh tests/run.sh
emulate -L zsh

ROOT="${0:A:h:h}"
typeset -g pass=0 fail=0

assert_eq() {
  local name="$1" exp="$2" act="$3"
  if [[ "$exp" == "$act" ]]; then
    (( pass++ ))
  else
    (( fail++ ))
    print -r -- "FAIL: $name"
    print -r -- "  expected: $exp"
    print -r -- "  actual:   $act"
  fi
}

# Sandbox: nothing in these tests may touch the real $HOME state
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Plain style so output lines are assertable
TT_PREFIX="[t]" TT_SEP="-" TT_C_PREFIX="" TT_C_TERM="" TT_C_TEXT="" TT_C_RESET=""
TT_DICT_DIR="$TMP/dict"
TT_SEEN_FILE="$TMP/seen"
mkdir -p "$TT_DICT_DIR"
: > "$TT_SEEN_FILE"

source "$ROOT/lib/parser.zsh"
source "$ROOT/lib/explain.zsh"

# === SUMMARY ===
print ""
print "tests: $((pass+fail))  passed: $pass  failed: $fail"
(( fail == 0 ))
