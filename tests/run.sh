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
# seg_join: renders TT_SEGMENTS for assertions; ' ;; ' is just the display join separator
# (segments internally use \x1f as the word separator within each segment).
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

tt_split "ls foo 2>&1"
assert_eq "split: fd redirect combined" "ls foo" "$(seg_join)"
assert_eq "split: fd redirect op" "2>&1" "${(j: :)TT_OPS}"

tt_split "cat << EOF"
assert_eq "split: heredoc marker consumed" "cat" "$(seg_join)"
assert_eq "split: heredoc op" "<<" "${(j: :)TT_OPS}"

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

tt_tokenize "env${SEP}FOO=bar${SEP}python"
assert_eq "tok: env assignment" "cmd:env word:FOO=bar cmd:python" "$(tok_join)"

tt_tokenize "grep${SEP}--${SEP}-v"
assert_eq "tok: dashes end flags" "cmd:grep arg:-- word:-v" "$(tok_join)"

# --- tt_dict_get ---
cat > "$TT_DICT_DIR/foo" <<'EOF'
# fixture command
summary a test command for the suite
sub run runs the thing
flag -a option a
flag --all every item
arg url an internet address
EOF

assert_eq "dict: summary" "a test command for the suite" "$(tt_dict_get foo summary)"
assert_eq "dict: sub" "runs the thing" "$(tt_dict_get foo sub run)"
assert_eq "dict: short flag" "option a" "$(tt_dict_get foo flag -a)"
assert_eq "dict: long flag" "every item" "$(tt_dict_get foo flag --all)"
assert_eq "dict: arg url" "an internet address" "$(tt_dict_get foo arg url)"
tt_dict_get foo flag -z; assert_eq "dict: miss returns 1" "1" "$?"
tt_dict_get nosuchcmd summary; assert_eq "dict: missing file returns 1" "1" "$?"

cat > "$TT_DICT_DIR/badsum" <<'EOF'
summary
flag -a still works
EOF
tt_dict_get badsum summary; assert_eq "dict: bare summary skipped" "1" "$?"
assert_eq "dict: file still usable" "still works" "$(tt_dict_get badsum flag -a)"

# --- tt_line / tt_seen / tt_mark / tt_explain_op ---
cat > "$TT_DICT_DIR/_operators" <<'EOF'
op | pipe: sends the output of the left command into the right command
op && and: run the right command only if the left one succeeded
EOF

typeset -a TT_OUT TT_NEWLY_SEEN
TT_OUT=() TT_NEWLY_SEEN=()
tt_line 0 "foo" "a test command"
tt_line 1 "-a" "option a"
assert_eq "line: top level" "[t] foo - a test command" "${TT_OUT[1]}"
assert_eq "line: indented" "[t]   -a - option a" "${TT_OUT[2]}"

tt_seen "zzz"; assert_eq "seen: unknown is unseen" "1" "$?"
tt_mark "zzz"
tt_seen "zzz"; assert_eq "seen: marked in memory" "0" "$?"
print "yyy" >> "$TT_SEEN_FILE"
tt_seen "yyy"; assert_eq "seen: found in file" "0" "$?"

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_op "|" new
assert_eq "op: explained" "[t] | - pipe: sends the output of the left command into the right command" "${TT_OUT[1]}"
assert_eq "op: marked" "op:|" "${TT_NEWLY_SEEN[1]}"
TT_OUT=()
tt_explain_op "|" new
assert_eq "op: silent second time" "0" "${#TT_OUT}"
TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_op "|" all
assert_eq "op: all mode ignores seen" "1" "${#TT_OUT}"
TT_OUT=()
tt_explain_op ">" new
assert_eq "op: unknown op silent" "0" "${#TT_OUT}"

# === SUMMARY ===
print ""
print "tests: $((pass+fail))  passed: $pass  failed: $fail"
(( fail == 0 ))
