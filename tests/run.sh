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
assert_eq "tok: bundle expands" "cmd:ls flag:-la" "$(tok_join)"

tt_tokenize "git${SEP}clone${SEP}--depth=1"
assert_eq "tok: long flag value stripped" "cmd:git word:clone flag:--depth" "$(tok_join)"

tt_tokenize "sudo${SEP}rm${SEP}-rf${SEP}/tmp/x"
assert_eq "tok: sudo prefix" "cmd:sudo cmd:rm flag:-rf word:/tmp/x" "$(tok_join)"

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

# --- tt_explain_segment (all mode) ---
out_join() { print -r -- "${(F)TT_OUT}" }

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "foo${SEP}-a${SEP}run" all
assert_eq "seg-all: summary+flag+sub" \
"[t] foo - a test command for the suite
[t]   -a - option a
[t]   run - runs the thing" "$(out_join)"

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "foo${SEP}-z" all
assert_eq "seg-all: unknown flag fallback" \
"[t] foo - a test command for the suite
[t]   -z - (no entry for this option)" "$(out_join)"

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "nosuchcmd${SEP}-x" all
assert_eq "seg-all: unknown command" \
"[t] nosuchcmd - not in my dictionary (try: man nosuchcmd, or ask Claude)" "$(out_join)"

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "foo${SEP}https://github.com/foo/bar" all
assert_eq "seg-all: url arg" \
"[t] foo - a test command for the suite
[t]   https://github.com/foo/bar - an internet address" "$(out_join)"

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "./script.sh${SEP}-x" all
assert_eq "seg-all: path-like cmd skipped" "0" "${#TT_OUT}"

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "../foo" all
assert_eq "seg-all: traversal skipped" "0" "${#TT_OUT}"

# --- tt_explain_segment (new mode) ---
flush_seen() { (( ${#TT_NEWLY_SEEN} )) && print -rl -- "${TT_NEWLY_SEEN[@]}" >> "$TT_SEEN_FILE"; TT_NEWLY_SEEN=() }
: > "$TT_SEEN_FILE"

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "foo${SEP}-a" new
assert_eq "seg-new: first use teaches both" "2" "${#TT_OUT}"
flush_seen

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "foo${SEP}-a" new
assert_eq "seg-new: second use silent" "0" "${#TT_OUT}"

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "foo${SEP}-a${SEP}--all" new
assert_eq "seg-new: only the new flag" "[t]   --all - every item" "$(out_join)"
flush_seen

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "nosuchcmd" new
assert_eq "seg-new: unknown once" "1" "${#TT_OUT}"
flush_seen
TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "nosuchcmd" new
assert_eq "seg-new: unknown silent after" "0" "${#TT_OUT}"

# repeat within one line must not double-print (in-memory dedupe)
: > "$TT_SEEN_FILE"
TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "foo${SEP}-a" new
tt_explain_segment "foo${SEP}-a" new
assert_eq "seg-new: same line dedupe" "2" "${#TT_OUT}"

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "foo${SEP}run" new
flush_seen
TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "foo${SEP}run" new
assert_eq "seg-new: seen sub silent" "0" "${#TT_OUT}"

# --- long single-dash flags vs bundles ---
cat > "$TT_DICT_DIR/fnd" <<'EOF'
summary searches for files
flag -name match files by name pattern
EOF
cat > "$TT_DICT_DIR/lss" <<'EOF'
summary lists files
flag -l long view
flag -a hidden files too
EOF

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "fnd${SEP}-name" all
assert_eq "flags: whole flag wins" \
"[t] fnd - searches for files
[t]   -name - match files by name pattern" "$(out_join)"

TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "lss${SEP}-la" all
assert_eq "flags: bundle explodes on miss" \
"[t] lss - lists files
[t]   -l - long view
[t]   -a - hidden files too" "$(out_join)"

: > "$TT_SEEN_FILE"
TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "lss${SEP}-la" new
flush_seen
TT_OUT=() TT_NEWLY_SEEN=()
tt_explain_segment "lss${SEP}-l" new
assert_eq "flags: exploded chars marked individually" "0" "${#TT_OUT}"

# --- plugin wiring (hook, explain, tutor) ---
# Load the full plugin in a sandboxed HOME, with the REAL dictionary.
export TUTOR_HOME="$TMP/fakehome"
mkdir -p "$TUTOR_HOME"
source "$ROOT/terminal-tutor.zsh"
# Re-apply plain test style (plugin reset the style globals)
TT_PREFIX="[t]" TT_SEP="-" TT_C_PREFIX="" TT_C_TERM="" TT_C_TEXT="" TT_C_RESET=""

out="$(tt_preexec 'ls -l')"
assert_eq "hook: teaches on first use" "0" "$?"
[[ "$out" == *"[t] ls -"* ]] && hookline=ok || hookline="missing: $out"
assert_eq "hook: ls summary printed" "ok" "$hookline"

out="$(tt_preexec 'ls -l')"
assert_eq "hook: silent on second use" "" "$out"

print off > "$TT_STATE_FILE"
out="$(tt_preexec 'pwd')"
assert_eq "hook: respects tutor off" "" "$out"
print on > "$TT_STATE_FILE"

out="$(explain ls -l)"
[[ "$out" == *"[t] ls -"*$'\n'*"[t]   -l -"* ]] && exok=ok || exok="bad: $out"
assert_eq "explain: full breakdown anytime" "ok" "$exok"

out="$(explain)"
[[ "$out" == Usage:* ]] && usok=ok || usok="bad: $out"
assert_eq "explain: usage when no args" "ok" "$usok"

tutor off >/dev/null
assert_eq "tutor: off written" "off" "$(<"$TT_STATE_FILE")"
tutor on >/dev/null
assert_eq "tutor: on written" "on" "$(<"$TT_STATE_FILE")"
print "ls" >> "$TT_SEEN_FILE"
tutor reset >/dev/null
assert_eq "tutor: reset clears seen" "0" "$(grep -c '' "$TT_SEEN_FILE")"
out="$(tutor status)"
[[ "$out" == *"on"*"learned"* ]] && stok=ok || stok="bad: $out"
assert_eq "tutor: status reports" "ok" "$stok"

# Fix 1: tutor on/off/reset survive a missing state dir
rm -rf "$TT_STATE_DIR"
out="$(tutor off 2>&1)"
assert_eq "tutor: off survives missing dir" "off" "$(<"$TT_STATE_FILE")"
[[ "$out" == *OFF* && "$out" != *"no such file"* ]] && offok=ok || offok="bad: $out"
assert_eq "tutor: off message clean" "ok" "$offok"
tutor on >/dev/null 2>&1

# Fix 2: state checks read only the first line of the state file
printf 'off\njunk line\n' > "$TT_STATE_FILE"
out="$(tt_preexec 'pwd')"
assert_eq "hook: off honored with trailing junk" "" "$out"
out="$(tutor status)"
[[ "$out" == "terminal-tutor: off | "* ]] && stok2=ok || stok2="bad: $out"
assert_eq "tutor: status first line only" "ok" "$stok2"
print on > "$TT_STATE_FILE"

unset TUTOR_HOME

# --- install / uninstall ---
IH="$TMP/inst_home"; mkdir -p "$IH"
IZ="$IH/.zshrc"
print "# my existing zshrc" > "$IZ"
print "export FOO=bar" >> "$IZ"
orig="$(<"$IZ")"

TUTOR_HOME="$IH" TUTOR_ZSHRC="$IZ" bash "$ROOT/install.sh" --local >/dev/null
assert_eq "install: exits 0" "0" "$?"
grep -qF "# >>> terminal-tutor >>>" "$IZ"; assert_eq "install: block added" "0" "$?"
[[ -L "$IH/.terminal-tutor/app" ]]; assert_eq "install: --local symlinks" "0" "$?"
[[ -f "$IH/.terminal-tutor/seen" ]]; assert_eq "install: seen created" "0" "$?"

TUTOR_HOME="$IH" TUTOR_ZSHRC="$IZ" bash "$ROOT/install.sh" --local >/dev/null
assert_eq "install: idempotent block" "1" "$(grep -cF '# >>> terminal-tutor >>>' "$IZ")"

TUTOR_HOME="$IH" TUTOR_ZSHRC="$IZ" bash "$ROOT/uninstall.sh" >/dev/null
assert_eq "uninstall: exits 0" "0" "$?"
assert_eq "uninstall: zshrc restored" "$orig" "$(<"$IZ")"
[[ ! -e "$IH/.terminal-tutor" ]]; assert_eq "uninstall: state removed" "0" "$?"

TUTOR_HOME="$IH" TUTOR_ZSHRC="$IZ" bash "$ROOT/uninstall.sh" >/dev/null
assert_eq "uninstall: safe to run twice" "0" "$?"

# a user-written start marker with no end marker must never trigger the
# block delete (an unterminated sed range would wipe to end of file)
print "# >>> terminal-tutor >>>" > "$IZ"
print "export KEEP=me" >> "$IZ"
TUTOR_HOME="$IH" TUTOR_ZSHRC="$IZ" bash "$ROOT/uninstall.sh" >/dev/null
grep -qF "export KEEP=me" "$IZ"; assert_eq "uninstall: unterminated marker safe" "0" "$?"

# === SUMMARY ===
print ""
print "tests: $((pass+fail))  passed: $pass  failed: $fail"
(( fail == 0 ))
