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

# --- tt_split ---
seg_join() { print -r -- "${(j: ;; :)${(@)TT_SEGMENTS//$'\x1f'/ }}" }

tt_split "ls -la"
assert_eq "split: single segment" "ls -la" "$(seg_join)"
assert_eq "split: no ops" "" "${(j: :)TT_OPS}"

tt_split "ls -la | grep foo && echo hi"
assert_eq "split: three segments" "ls -la ;; grep foo ;; echo hi" "$(seg_join)"
assert_eq "split: pipe and and" "| &&" "${(j: :)TT_OPS}"

tt_split "echo hi > out.txt"
assert_eq "split: redirect target consumed" "echo hi" "$(seg_join)"
assert_eq "split: redirect op recorded" ">" "${(j: :)TT_OPS}"

tt_split "cat a.txt | grep x | wc -l"
assert_eq "split: op deduped" "|" "${(j: :)TT_OPS}"

tt_split 'grep "hello world" f.txt'
assert_eq "split: quoted arg intact" 'grep "hello world" f.txt' "$(seg_join)"

# --- tt_tokenize ---
tok_join() { print -r -- "${(j: :)TT_TOKENS}" }
SEP=$'\x1f'

tt_tokenize "git${SEP}clone${SEP}https://github.com/foo/bar"
assert_eq "tok: cmd word word" "cmd:git word:clone word:https://github.com/foo/bar" "$(tok_join)"

tt_tokenize "ls${SEP}-la"
assert_eq "tok: bundle expands" "cmd:ls flag:-l flag:-a" "$(tok_join)"

tt_tokenize "git${SEP}clone${SEP}--depth=1"
assert_eq "tok: long flag value stripped" "cmd:git word:clone flag:--depth" "$(tok_join)"

tt_tokenize "sudo${SEP}rm${SEP}-rf${SEP}/tmp/x"
assert_eq "tok: sudo prefix" "cmd:sudo cmd:rm flag:-r flag:-f word:/tmp/x" "$(tok_join)"

tt_tokenize "grep${SEP}\"hello world\"${SEP}f.txt"
assert_eq "tok: quoted word untouched" 'cmd:grep word:"hello world" word:f.txt' "$(tok_join)"

tt_tokenize "kill${SEP}-9${SEP}1234"
assert_eq "tok: numeric flag" "cmd:kill flag:-9 word:1234" "$(tok_join)"

# === SUMMARY ===
print ""
print "tests: $((pass+fail))  passed: $pass  failed: $fail"
(( fail == 0 ))
