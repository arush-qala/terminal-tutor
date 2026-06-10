# terminal-tutor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a zero-dependency zsh plugin that teaches Arush (a non-engineer) what terminal commands mean the first time he runs them, with on-demand `explain`, a `tutor` control command, one-line install/uninstall via GitHub, and a user-chosen visual style.

**Architecture:** A `preexec` hook (zsh's "command about to run" event) parses the typed line with pure-zsh functions (`lib/parser.zsh`), looks pieces up in a folder of plain-text dictionary files, and prints first-time explanations (`lib/explain.zsh`). State (what's been taught) lives in `~/.terminal-tutor/seen`. Bash installer/uninstaller manage a marked block in `~/.zshrc`.

**Tech Stack:** zsh (plugin + tests), bash (install/uninstall), git + GitHub (`gh` CLI), one single-file HTML style playground.

**Project root (all paths below are relative to it):**
`<project-root>`

**Spec:** `docs/superpowers/specs/2026-06-10-terminal-tutor-design.md`

**Conventions for every task:**
- Run all commands from the project root.
- Tests live in `tests/run.sh`; each task INSERTS its test section ABOVE the `# === SUMMARY ===` marker line and never deletes earlier sections.
- Run the suite with: `zsh tests/run.sh` — expected output ends `failed: 0` and exit code 0.
- End every git commit message with the trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` (omitted from the snippets below for brevity).
- Dictionary file format is WHITESPACE-separated (NOT tabs): `summary <text…>`, `sub <name> <text…>`, `flag <-x|--xx> <text…>`, `arg url <text…>`, `op <symbol> <text…>` (operators file only). `#` starts a comment line.
- Tone rule for ALL dictionary text and user-facing messages: plain English for a non-engineer; no unexplained jargon; lowercase sentence fragments; ≤ 90 characters per explanation.

---

### Task 1: Project skeleton, config, and test harness

**Files:**
- Create: `terminal-tutor.zsh`
- Create: `lib/parser.zsh`
- Create: `lib/explain.zsh`
- Create: `tests/run.sh`
- Create: `dictionary/.gitkeep` (empty file so the folder exists in git)

- [ ] **Step 1: Create folders and empty lib files**

```bash
mkdir -p lib tests dictionary tools
touch dictionary/.gitkeep
```

- [ ] **Step 2: Write `terminal-tutor.zsh` (config + style + sourcing only for now)**

```zsh
# terminal-tutor - learn what your commands mean as you type them.
# Loaded from ~/.zshrc via the marked block added by install.sh.
# Docs: README.md in this folder.

# Where this file lives (resolves symlinks, so --local installs work)
typeset -g TT_DIR="${${(%):-%N}:A:h}"

# Per-machine state (TUTOR_HOME override exists only so tests can sandbox)
typeset -g TT_STATE_DIR="${TUTOR_HOME:-$HOME}/.terminal-tutor"
typeset -g TT_SEEN_FILE="$TT_STATE_DIR/seen"
typeset -g TT_STATE_FILE="$TT_STATE_DIR/state"
typeset -g TT_DICT_DIR="$TT_DIR/dictionary"

mkdir -p "$TT_STATE_DIR" 2>/dev/null
[[ -f "$TT_SEEN_FILE" ]] || : > "$TT_SEEN_FILE"
[[ -f "$TT_STATE_FILE" ]] || print on > "$TT_STATE_FILE"

# --- Style (defaults; final values chosen by Arush via tools/style-playground.html) ---
typeset -g TT_PREFIX="[tutor]"
typeset -g TT_SEP="—"
typeset -g TT_C_PREFIX=$'\e[2;36m'   # dim cyan
typeset -g TT_C_TERM=$'\e[1;36m'     # bright cyan
typeset -g TT_C_TEXT=$'\e[2m'        # dim
typeset -g TT_C_RESET=$'\e[0m'

source "$TT_DIR/lib/parser.zsh"
source "$TT_DIR/lib/explain.zsh"
```

- [ ] **Step 3: Write the test harness `tests/run.sh`**

```zsh
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
```

- [ ] **Step 4: Run the (empty) suite to verify the harness works**

Run: `zsh tests/run.sh`
Expected: `tests: 0  passed: 0  failed: 0`, exit code 0 (check with `echo $?`).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: project skeleton, plugin config, test harness"
```

---

### Task 2: Parser — split a command line into segments and operators

`tt_split` takes the raw typed line and fills two global arrays: `TT_SEGMENTS` (each element = one command's words joined by the `\x1f` control character, so quoted words containing spaces survive) and `TT_OPS` (deduped shell operators encountered). Redirection operators consume their filename target so it is not mistaken for a command.

**Files:**
- Modify: `lib/parser.zsh`
- Test: `tests/run.sh`

- [ ] **Step 1: Write the failing tests** (insert above `# === SUMMARY ===`)

```zsh
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/run.sh`
Expected: FAIL lines (tt_split not defined → empty actuals), `failed:` > 0.

- [ ] **Step 3: Implement `tt_split` in `lib/parser.zsh`**

```zsh
# terminal-tutor parser: pure functions, no file or terminal I/O.

# tt_split <command line>
# Sets: TT_SEGMENTS - array; each element = one command's words joined by \x1f
#       TT_OPS      - array of shell operators seen (deduped, in order)
# Redirection operators (> >> < etc.) consume the word after them (the file),
# so filenames are never mistaken for commands.
tt_split() {
  emulate -L zsh
  local -a words cur
  local w skip_next=0
  TT_SEGMENTS=() TT_OPS=()
  words=(${(z)1})
  for w in "${words[@]}"; do
    if (( skip_next )); then skip_next=0; continue; fi
    case "$w" in
      '|'|'||'|'&&'|';'|'&'|'|&')
        (( ${#cur} )) && TT_SEGMENTS+=("${(pj:\x1f:)cur}")
        cur=()
        (( ${TT_OPS[(Ie)$w]} )) || TT_OPS+=("$w")
        ;;
      '>'|'>>'|'<'|'&>'|'&>>'|[0-9]'>'|[0-9]'>>')
        (( ${TT_OPS[(Ie)$w]} )) || TT_OPS+=("$w")
        skip_next=1
        ;;
      [0-9]'>&'[0-9])
        (( ${TT_OPS[(Ie)$w]} )) || TT_OPS+=("$w")
        ;;
      *) cur+=("$w") ;;
    esac
  done
  (( ${#cur} )) && TT_SEGMENTS+=("${(pj:\x1f:)cur}")
  return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh tests/run.sh` — Expected: `failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add lib/parser.zsh tests/run.sh
git commit -m "feat: tt_split segments command lines and records operators"
```

---

### Task 3: Parser — tokenize one segment

`tt_tokenize` turns one segment into `TT_TOKENS` entries `type:value` where type ∈ `cmd`, `flag`, `word`, `arg`. Rules: first word is `cmd`; `sudo`/`env` stay in "expecting a command" state so the real command is also tagged `cmd`; bundled short flags expand (`-la` → `-l` `-a`); `--flag=value` keeps only `--flag`; quoted strings are single `word` tokens, never flag-parsed.

**Files:**
- Modify: `lib/parser.zsh`
- Test: `tests/run.sh`

- [ ] **Step 1: Write the failing tests** (insert above `# === SUMMARY ===`)

```zsh
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/run.sh` — Expected: new FAIL lines for tok tests.

- [ ] **Step 3: Implement `tt_tokenize` in `lib/parser.zsh`** (append to the file)

```zsh
# tt_tokenize <segment (words joined by \x1f)>
# Sets TT_TOKENS - array of "type:value" with type: cmd | flag | word | arg
tt_tokenize() {
  emulate -L zsh
  local -a words
  words=("${(ps:\x1f:)1}")
  TT_TOKENS=()
  local w i expecting_cmd=1
  for w in "${words[@]}"; do
    if (( expecting_cmd )) && [[ "$w" != -* ]]; then
      TT_TOKENS+=("cmd:$w")
      [[ "$w" == sudo || "$w" == env ]] || expecting_cmd=0
      continue
    fi
    case "$w" in
      --) TT_TOKENS+=("arg:--") ;;
      --*) TT_TOKENS+=("flag:${w%%=*}") ;;
      -[A-Za-z0-9]) TT_TOKENS+=("flag:$w") ;;
      -[A-Za-z][A-Za-z]*)
        for (( i=2; i <= ${#w}; i++ )); do TT_TOKENS+=("flag:-${w[i]}"); done ;;
      -*) TT_TOKENS+=("flag:$w") ;;
      *) TT_TOKENS+=("word:$w") ;;
    esac
  done
  return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh tests/run.sh` — Expected: `failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add lib/parser.zsh tests/run.sh
git commit -m "feat: tt_tokenize classifies cmd/flag/word tokens"
```

---

### Task 4: Dictionary lookup

`tt_dict_get <command> <type> [key]` reads `dictionary/<command>` and prints the matching explanation. Whitespace-separated format; malformed/comment lines are skipped; returns 1 when not found.

**Files:**
- Modify: `lib/explain.zsh`
- Test: `tests/run.sh`

- [ ] **Step 1: Write the failing tests** (insert above `# === SUMMARY ===`)

```zsh
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/run.sh` — Expected: FAILs (tt_dict_get not defined).

- [ ] **Step 3: Implement `tt_dict_get` in `lib/explain.zsh`**

```zsh
# terminal-tutor explain engine: dictionary lookup, seen-state, line building.

# tt_dict_get <command> <type: summary|sub|flag|arg|op> [key]
# Prints the explanation text from dictionary/<command>; returns 1 if absent.
tt_dict_get() {
  emulate -L zsh
  local file="$TT_DICT_DIR/$1" type="$2" key="${3:-}"
  [[ -r "$file" ]] || return 1
  local f1 f2 rest
  while read -r f1 f2 rest; do
    case "$f1" in
      ''|\#*) continue ;;
      summary)
        if [[ "$type" == summary ]]; then
          print -r -- "$f2${rest:+ $rest}"
          return 0
        fi
        ;;
      *)
        if [[ "$f1" == "$type" && "$f2" == "$key" && -n "$rest" ]]; then
          print -r -- "$rest"
          return 0
        fi
        ;;
    esac
  done < "$file"
  return 1
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh tests/run.sh` — Expected: `failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add lib/explain.zsh tests/run.sh
git commit -m "feat: tt_dict_get reads dictionary files"
```

---

### Task 5: Output line builder, seen-state helpers, operator explainer

Three tiny helpers shared by hook and `explain`: `tt_line` (append a styled line to `TT_OUT`), `tt_seen`/`tt_mark` (seen-file + in-flight memory), `tt_explain_op` (explain `|`, `&&` etc. from `dictionary/_operators`).

**Files:**
- Modify: `lib/explain.zsh`
- Create: `dictionary/_operators`
- Test: `tests/run.sh`

- [ ] **Step 1: Write the failing tests** (insert above `# === SUMMARY ===`)

```zsh
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/run.sh` — Expected: FAILs for the new section.

- [ ] **Step 3: Implement the helpers in `lib/explain.zsh`** (append)

```zsh
# tt_line <indent 0|1> <term> <text>  - appends one styled line to TT_OUT
tt_line() {
  local pad=""
  (( $1 )) && pad="  "
  TT_OUT+=("${TT_C_PREFIX}${TT_PREFIX}${TT_C_RESET} ${pad}${TT_C_TERM}${2}${TT_C_RESET} ${TT_C_TEXT}${TT_SEP} ${3}${TT_C_RESET}")
}

# tt_seen <key> - 0 if already taught (this command line or the seen file)
tt_seen() {
  (( ${TT_NEWLY_SEEN[(Ie)$1]} )) && return 0
  grep -qxF -- "$1" "$TT_SEEN_FILE" 2>/dev/null
}

# tt_mark <key> - remember a key as taught (written to file by the caller)
tt_mark() { TT_NEWLY_SEEN+=("$1") }

# tt_explain_op <operator> <mode: new|all>
tt_explain_op() {
  emulate -L zsh
  local op="$1" mode="$2" text
  [[ "$mode" == new ]] && tt_seen "op:$op" && return 0
  text="$(tt_dict_get _operators op "$op")" || return 0
  tt_line 0 "$op" "$text"
  [[ "$mode" == new ]] && tt_mark "op:$op"
  return 0
}
```

- [ ] **Step 4: Write the real `dictionary/_operators`**

```
# shell operators (looked up by tt_explain_op)
op | pipe: sends the output of the left command into the right command as its input
op && and-then: run the right command only if the left one finished without error
op || or-else: run the right command only if the left one failed
op ; then: run the commands one after another, regardless of errors
op & background: run the command in the background so you can keep typing
op > save-to-file: write the command's output into a file (replacing it)
op >> append-to-file: add the command's output to the end of a file
op < read-from-file: feed a file into the command as its input
op |& pipe-all: like | but also sends error messages across
op 2> errors-to-file: write only the error messages into a file
op 2>&1 merge: send error messages to the same place as normal output
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `zsh tests/run.sh` — Expected: `failed: 0`. (Tests use the fixture `_operators` in `$TMP`, not the real one — both must parse.)

- [ ] **Step 6: Commit**

```bash
git add lib/explain.zsh dictionary/_operators tests/run.sh
git commit -m "feat: line builder, seen-state helpers, operator explainer"
```

---

### Task 6: Segment explainer — `all` mode

`tt_explain_segment <segment> <mode>` is the core. This task implements `all` mode (used by the `explain` command): explain everything, ignore the seen file. Covers: command summary, unknown commands, flags (with "no entry" fallback in all-mode only), first bare word as subcommand, URL arguments.

**Files:**
- Modify: `lib/explain.zsh`
- Test: `tests/run.sh`

- [ ] **Step 1: Write the failing tests** (insert above `# === SUMMARY ===`)

```zsh
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/run.sh` — Expected: FAILs (function missing).

- [ ] **Step 3: Implement `tt_explain_segment` in `lib/explain.zsh`** (append)

```zsh
# tt_explain_segment <segment (words joined by \x1f)> <mode: new|all>
# Appends explanation lines to TT_OUT; in "new" mode appends taught keys
# to TT_NEWLY_SEEN and skips anything already seen.
tt_explain_segment() {
  emulate -L zsh
  local seg="$1" mode="$2"
  local -a TT_TOKENS
  tt_tokenize "$seg"
  local tok type val cmd="" sub_checked=0 text short
  for tok in "${TT_TOKENS[@]}"; do
    type="${tok%%:*}"; val="${tok#*:}"
    case "$type" in
      cmd)
        cmd="$val"; sub_checked=0
        if [[ ! -r "$TT_DICT_DIR/$cmd" ]]; then
          if [[ "$mode" == all ]]; then
            tt_line 0 "$cmd" "not in my dictionary (try: man $cmd, or ask Claude)"
          elif ! tt_seen "unknown:$cmd"; then
            tt_line 0 "$cmd" "not in my dictionary yet (try: man $cmd, or ask Claude)"
            tt_mark "unknown:$cmd"
          fi
          cmd=""
          continue
        fi
        if [[ "$mode" == all ]] || ! tt_seen "$cmd"; then
          if text="$(tt_dict_get "$cmd" summary)"; then
            tt_line 0 "$cmd" "$text"
          fi
          [[ "$mode" == new ]] && tt_mark "$cmd"
        fi
        ;;
      flag)
        [[ -z "$cmd" ]] && continue
        if [[ "$mode" == all ]] || ! tt_seen "$cmd $val"; then
          if text="$(tt_dict_get "$cmd" flag "$val")"; then
            tt_line 1 "$val" "$text"
            [[ "$mode" == new ]] && tt_mark "$cmd $val"
          elif [[ "$mode" == all ]]; then
            tt_line 1 "$val" "(no entry for this option)"
          fi
        fi
        ;;
      word)
        [[ -z "$cmd" ]] && continue
        if (( ! sub_checked )); then
          sub_checked=1
          if text="$(tt_dict_get "$cmd" sub "$val")"; then
            if [[ "$mode" == all ]] || ! tt_seen "$cmd $val"; then
              tt_line 1 "$val" "$text"
              [[ "$mode" == new ]] && tt_mark "$cmd $val"
            fi
            continue
          fi
        fi
        if [[ "$val" == http://* || "$val" == https://* ]]; then
          if text="$(tt_dict_get "$cmd" arg url)"; then
            if [[ "$mode" == all ]] || ! tt_seen "$cmd arg:url"; then
              short="$val"
              (( ${#val} > 42 )) && short="${val[1,40]}…"
              tt_line 1 "$short" "$text"
              [[ "$mode" == new ]] && tt_mark "$cmd arg:url"
            fi
          fi
        fi
        ;;
    esac
  done
  return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh tests/run.sh` — Expected: `failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add lib/explain.zsh tests/run.sh
git commit -m "feat: tt_explain_segment all mode"
```

---

### Task 7: Segment explainer — `new` mode (first-time teaching memory)

Same function, `new` mode: teach once, stay silent after; a new flag on a known command teaches only that flag; unknown commands nag exactly once.

**Files:**
- Modify: `lib/explain.zsh` (only if tests reveal bugs — the Task 6 code already branches on mode)
- Test: `tests/run.sh`

- [ ] **Step 1: Write the tests** (insert above `# === SUMMARY ===`)

```zsh
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
```

- [ ] **Step 2: Run tests**

Run: `zsh tests/run.sh`
Expected: `failed: 0` (Task 6's implementation already handles mode=new). If any FAIL, fix `tt_explain_segment` until green — the seen-key formats are: command `foo`, flag `foo -a`, sub `foo run`, url `foo arg:url`, unknown `unknown:foo`, operator `op:|`.

- [ ] **Step 3: Commit**

```bash
git add tests/run.sh
git commit -m "test: first-time teaching memory (new mode)"
```

---

### Task 8: Main plugin — preexec hook, `explain`, `tutor`

Wire everything into `terminal-tutor.zsh`: the guarded `preexec` hook, the `explain` user command, and the `tutor` control command.

**Files:**
- Modify: `terminal-tutor.zsh`
- Test: `tests/run.sh`

- [ ] **Step 1: Write the failing tests** (insert above `# === SUMMARY ===`)

```zsh
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
unset TUTOR_HOME
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/run.sh` — Expected: FAILs (`tt_preexec`, `explain`, `tutor` undefined). Note: `hook: teaches on first use` needs `dictionary/ls` to exist — if Task 9 hasn't run yet, create a minimal real `dictionary/ls` in THIS task (content given in Task 9, Step 1; copy it from there now).

- [ ] **Step 3: Implement in `terminal-tutor.zsh`** (append below the two `source` lines)

```zsh
# --- the hook: runs just before every command; must never break anything ---
tt_preexec() {
  setopt localoptions noerrexit
  {
    [[ -r "$TT_STATE_FILE" && "$(<"$TT_STATE_FILE")" == off ]] && return 0
    local -a TT_OUT TT_NEWLY_SEEN TT_SEGMENTS TT_OPS
    TT_OUT=() TT_NEWLY_SEEN=()
    tt_split "$1"
    local seg op
    for seg in "${TT_SEGMENTS[@]}"; do tt_explain_segment "$seg" new; done
    for op in "${TT_OPS[@]}"; do tt_explain_op "$op" new; done
    (( ${#TT_OUT} )) && print -rl -- "${TT_OUT[@]}"
    (( ${#TT_NEWLY_SEEN} )) && print -rl -- "${TT_NEWLY_SEEN[@]}" >> "$TT_SEEN_FILE"
  } 2>/dev/null
  return 0
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec tt_preexec

# --- explain: full breakdown on demand, e.g.  explain ls -la ---
explain() {
  emulate -L zsh
  if (( $# == 0 )); then
    print "Usage: explain <command>     e.g.  explain ls -la"
    print "Tip: put quotes around lines with | or > :  explain 'cat log | grep error'"
    return 0
  fi
  local -a TT_OUT TT_NEWLY_SEEN TT_SEGMENTS TT_OPS
  TT_OUT=() TT_NEWLY_SEEN=()
  tt_split "$*"
  local seg op
  for seg in "${TT_SEGMENTS[@]}"; do tt_explain_segment "$seg" all; done
  for op in "${TT_OPS[@]}"; do tt_explain_op "$op" all; done
  if (( ${#TT_OUT} )); then
    print -rl -- "${TT_OUT[@]}"
  else
    print "Nothing I can explain there."
  fi
  return 0
}

# --- tutor: control command ---
tutor() {
  emulate -L zsh
  case "${1:-}" in
    on)
      print on > "$TT_STATE_FILE"
      print "terminal-tutor: ON - new commands will be explained." ;;
    off)
      print off > "$TT_STATE_FILE"
      print "terminal-tutor: OFF - run 'tutor on' to resume." ;;
    reset)
      : > "$TT_SEEN_FILE"
      print "terminal-tutor: memory cleared - everything will be taught again." ;;
    status)
      local state="on"
      [[ -r "$TT_STATE_FILE" ]] && state="$(<"$TT_STATE_FILE")"
      local learned=0
      [[ -r "$TT_SEEN_FILE" ]] && learned="$(grep -c '' "$TT_SEEN_FILE")"
      local -a dfiles
      dfiles=("$TT_DICT_DIR"/^_*(N))
      print "terminal-tutor: $state | things learned: $learned | commands in dictionary: ${#dfiles}" ;;
    uninstall)
      "$TT_DIR/uninstall.sh" ;;
    *)
      print "Usage: tutor on | off | reset | status | uninstall" ;;
  esac
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh tests/run.sh` — Expected: `failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add terminal-tutor.zsh tests/run.sh dictionary/
git commit -m "feat: preexec hook, explain and tutor commands"
```

---

### Task 9: Dictionary — exemplar files (exact content)

Create these files in `dictionary/` with EXACTLY this content (they define the voice for Task 10). No tabs needed — single spaces separate fields.

**Files:**
- Create: `dictionary/ls`, `dictionary/cd`, `dictionary/git`, `dictionary/brew`, `dictionary/curl`, `dictionary/chmod`, `dictionary/rm`, `dictionary/npm`, `dictionary/sudo`, `dictionary/explain`, `dictionary/tutor`

- [ ] **Step 1: Write the files**

`dictionary/ls`
```
summary list the files and folders in the current folder
flag -l long view: one file per line with size, owner and date
flag -a also show hidden files (names starting with a dot)
flag -h show sizes in human units like KB and MB
flag -t newest files first
flag -R also list inside every subfolder
```

`dictionary/cd`
```
summary change directory: move into another folder ('cd ..' goes up one level, plain 'cd' goes home)
```

`dictionary/git`
```
summary version control tool: tracks changes to code and moves projects to and from the internet
sub clone download a full copy of a project from an online address
sub status show what has changed since your last save point
sub add stage files so the next commit includes them
sub commit save a named snapshot of your staged changes
sub push upload your saved commits to the online copy (e.g. GitHub)
sub pull download the latest changes from the online copy
sub log list past commits, newest first
sub init turn the current folder into a git project
sub branch list or create parallel working versions of the project
sub checkout switch to another branch or version
sub diff show exactly which lines changed
flag -m the message describing a commit
flag -C run as if started inside the given folder
flag --version print which version of git is installed
flag --help show the help page
arg url the internet address of the project
```

`dictionary/brew`
```
summary Homebrew: the app store of the Mac terminal; installs command-line programs
sub install download and set up a program
sub uninstall remove a program that brew installed
sub update refresh brew's catalogue of available programs
sub upgrade install newer versions of programs you already have
sub list show everything brew has installed
sub search look for a program by name
sub info show details about a program before installing
sub doctor check your brew setup for problems
flag --cask install a regular Mac app (with a windowed interface) rather than a terminal tool
```

`dictionary/curl`
```
summary download from, or talk to, an internet address right from the terminal
flag -f fail silently instead of saving an error page
flag -s silent: hide the progress bar
flag -S but still show real errors (used together with -s)
flag -L follow redirects if the address has moved
flag -o save the download into the file you name
flag -O save the download using its original file name
flag -X choose the request type (GET fetches, POST sends)
flag -H add an extra header line to the request
flag -d the data to send with the request
arg url the internet address to fetch
```

`dictionary/chmod`
```
summary change a file's permissions (who may read, write or run it)
flag -R apply to a folder and everything inside it
sub +x make the file executable, i.e. runnable as a program (common after downloading scripts)
```

`dictionary/rm`
```
summary delete files - careful: there is no trash bin here, gone is gone
flag -r also delete folders and everything inside them
flag -f force: do not ask for confirmation
flag -i ask before each delete (safer)
```

`dictionary/npm`
```
summary the package manager for JavaScript tools; installs them into a project or your whole machine
sub install download a package (add -g to install it machine-wide as a command)
sub uninstall remove a package
sub run run a script defined by the project
sub start start the project (shorthand for npm run start)
sub init set up a new project in this folder
flag -g global: install machine-wide so you can use it anywhere
flag --version print which version of npm is installed
```

`dictionary/sudo`
```
summary run one command as the administrator; the Mac asks for your password first
flag -E keep your settings while running as administrator
```

`dictionary/explain`
```
summary part of terminal-tutor: type 'explain' before any command to get a plain-English breakdown
```

`dictionary/tutor`
```
summary controls terminal-tutor itself (on, off, reset, status, uninstall)
sub on resume automatic teaching
sub off pause automatic teaching
sub reset forget everything learned so it teaches from scratch
sub status show whether teaching is on and how much you have learned
sub uninstall remove terminal-tutor completely
```

- [ ] **Step 2: Spot-check lookups against the real dictionary**

```bash
zsh -c 'TT_DICT_DIR=dictionary; source lib/explain.zsh; tt_dict_get git sub clone; tt_dict_get brew flag --cask; tt_dict_get chmod sub +x'
```
Expected: the three explanation lines, no errors. (Note: `chmod +x` works because `+x` is a bare word → checked as a subcommand.)

- [ ] **Step 3: Run the full suite**

Run: `zsh tests/run.sh` — Expected: `failed: 0`.

- [ ] **Step 4: Commit**

```bash
git add dictionary/
git commit -m "feat: exemplar dictionary files"
```

---

### Task 10: Dictionary — full launch coverage (~95 commands)

Author the remaining files following the EXACT voice, format, and length rules of Task 9's exemplars (plain English, no jargon, ≤ 90 chars per explanation, lowercase fragments). For each command below: one `summary` line, plus a `flag`/`sub` line for each listed item. Items in parentheses are content hints, not text to copy.

**Files:**
- Create: one file per command in `dictionary/`

- [ ] **Step 1: Files & navigation**
`pwd` (summary only) · `mkdir`: -p · `rmdir` · `cp`: -r -i -v · `mv`: -i -v · `cat`: -n · `less` (mention: q quits) · `more` · `open`: -a -e (mac: open file/folder/app from terminal) · `touch` · `find`: -name -type -delete · `which` · `echo`: -n · `file` · `stat` · `head`: -n · `tail`: -n -f · `wc`: -l -w -c · `tree`: -L (note: install with brew)

- [ ] **Step 2: System & shell**
`chown`: -R · `kill`: -9 -l · `ps`: -e -f, sub aux (everything running) · `top`: -o · `htop` (note: install with brew) · `df`: -h · `du`: -h -s · `uname`: -a · `whoami` · `history` · `clear` · `export` (summary explains VAR=value) · `source` (run a file's commands in THIS shell; why install guides use it) · `alias` · `env` · `printenv` · `man` (the built-in manual; q quits) · `type` · `time` · `watch`: -n (note: install with brew) · `sleep` · `date` · `cal` · `say` · `exit` · `jobs` · `fg` · `bg`

- [ ] **Step 3: Text tools**
`grep`: -i -r -n -v -E · `sed`: -i -e -n · `awk`: -F · `sort`: -r -n -u · `uniq`: -c · `xargs`: -I -n · `tee`: -a · `jq`: -r (note: install with brew)

- [ ] **Step 4: Network**
`wget`: -O (note: install with brew) · `ssh`: -i -p · `ping`: -c · `scp`: -r

- [ ] **Step 5: Package managers & dev tools**
`npx` (run a JS tool without installing it): -y · `node`: -v, sub --version? (use flag --version) · `yarn`: subs install add · `pip` & `pip3` (same content, two files): subs install uninstall list show; flag -U · `pipx`: subs install run list · `uv`: subs pip venv run tool · `python` & `python3`: flag -m, flag -V · `conda`: subs activate deactivate install create env · `gh`: subs auth repo pr issue; flag --help · `docker`: subs run ps pull build images stop; flags -i -t

- [ ] **Step 6: Editors, clipboard, archives, AI tools**
`nano` (mention: Ctrl+X exits) · `vim` (mention: :q! quits) · `code` (opens VS Code; 'code .' opens current folder) · `pbcopy` (mac: pipe into it to copy) · `pbpaste` · `tar`: -x -c -z -v -f (the classic -xzvf combo) · `zip`: -r · `unzip`: -d · `gzip`: -d · `ditto` · `claude` (Anthropic's AI coding agent in the terminal): flag -p, flag --version · `gemini` (Google's AI agent CLI): flag --help · `codex` (OpenAI's AI agent CLI): flag --help · `ollama` (runs AI models locally): subs run pull list serve

- [ ] **Step 7: Verify every file parses and has a summary**

```bash
zsh -c '
TT_DICT_DIR=dictionary; source lib/explain.zsh
bad=0
for f in dictionary/^_*(N:t); do
  tt_dict_get "$f" summary >/dev/null || { print "NO SUMMARY: $f"; bad=1 }
done
(( bad )) && exit 1
print OK: ${#$(echo dictionary/^_*(N))} files'
```
Expected: `OK: <count> files`, no `NO SUMMARY` lines.

- [ ] **Step 8: Run the full suite, then commit**

Run: `zsh tests/run.sh` — Expected: `failed: 0`.

```bash
git add dictionary/
git commit -m "feat: full launch dictionary (~95 commands)"
```

---

### Task 11: install.sh and uninstall.sh

Bash scripts (the curl one-liner pipes to bash). `TUTOR_HOME`/`TUTOR_ZSHRC` env overrides exist ONLY for tests.

**Files:**
- Create: `install.sh`, `uninstall.sh`
- Test: `tests/run.sh`

- [ ] **Step 1: Write the failing tests** (insert above `# === SUMMARY ===`)

```zsh
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh tests/run.sh` — Expected: FAILs (scripts missing).

- [ ] **Step 3: Write `install.sh`**

```bash
#!/bin/bash
# terminal-tutor installer.
#   One-line install:  curl -fsSL https://raw.githubusercontent.com/REPO_OWNER/terminal-tutor/main/install.sh | bash
#   Developer mode:    ./install.sh --local   (symlinks this folder instead of cloning)
set -euo pipefail

REPO_URL="https://github.com/REPO_OWNER/terminal-tutor.git"   # REPO_OWNER is set in the GitHub task
TT_HOME="${TUTOR_HOME:-$HOME}"
ZSHRC="${TUTOR_ZSHRC:-$TT_HOME/.zshrc}"
STATE_DIR="$TT_HOME/.terminal-tutor"
APP_DIR="$STATE_DIR/app"
MARK_START="# >>> terminal-tutor >>>"
MARK_END="# <<< terminal-tutor <<<"

mkdir -p "$STATE_DIR"

if [[ "${1:-}" == "--local" ]]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  rm -rf "$APP_DIR"
  ln -sfn "$SRC_DIR" "$APP_DIR"
else
  if [[ -d "$APP_DIR/.git" ]]; then
    git -C "$APP_DIR" pull --quiet
  else
    rm -rf "$APP_DIR"
    git clone --quiet "$REPO_URL" "$APP_DIR"
  fi
fi

touch "$STATE_DIR/seen"
[[ -f "$STATE_DIR/state" ]] || echo on > "$STATE_DIR/state"

if ! grep -qF "$MARK_START" "$ZSHRC" 2>/dev/null; then
  {
    echo ""
    echo "$MARK_START"
    echo "source \"\$HOME/.terminal-tutor/app/terminal-tutor.zsh\""
    echo "$MARK_END"
  } >> "$ZSHRC"
fi

echo "terminal-tutor installed."
echo "Open a new Terminal window (or run: source ~/.zshrc) and it will start teaching."
```

- [ ] **Step 4: Write `uninstall.sh`**

```bash
#!/bin/bash
# terminal-tutor uninstaller. Removes the ~/.zshrc block and all state. Safe to run twice.
set -uo pipefail

TT_HOME="${TUTOR_HOME:-$HOME}"
ZSHRC="${TUTOR_ZSHRC:-$TT_HOME/.zshrc}"

if [[ -f "$ZSHRC" ]] && grep -qF "# >>> terminal-tutor >>>" "$ZSHRC"; then
  sed -i '' '/# >>> terminal-tutor >>>/,/# <<< terminal-tutor <<</d' "$ZSHRC"
  # the installer added a blank line before the block; drop a single trailing blank line
  if [[ -z "$(tail -n 1 "$ZSHRC")" ]]; then
    sed -i '' -e '$ d' "$ZSHRC"
  fi
fi

rm -rf "$TT_HOME/.terminal-tutor"

echo "terminal-tutor removed. Open a new Terminal window to finish."
```

- [ ] **Step 5: Make both executable, run tests**

```bash
chmod +x install.sh uninstall.sh
zsh tests/run.sh
```
Expected: `failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add install.sh uninstall.sh tests/run.sh
git commit -m "feat: install and uninstall scripts with marked zshrc block"
```

---

### Task 12: Visual style — playground for Arush, then apply his choices

⚠️ PAUSE POINTS: this task needs Arush in a browser.

**Files:**
- Create: `tools/style-playground.html`
- Modify: `terminal-tutor.zsh` (style constants)

- [ ] **Step 1: Build the playground** — invoke the `playground` skill (or hand-build a single self-contained HTML file at `tools/style-playground.html`) with these exact requirements:
  - A dark terminal-window mockup showing a realistic session: the user types `git clone https://github.com/foo/bar`, tutor lines appear, then normal command output; below it a second example `ls -la`.
  - Controls (live-updating the mockup):
    - **Prefix**: `[tutor]` / `📚` / `›` / `tip:` / none
    - **Color scheme**: dim gray / cyan / yellow-accent / green-accent (term name bright+colored, explanation dim)
    - **Separator**: `—` / `-` / `→` / `:`
    - **Layout**: indented breakdown (flags indented under command) / flat (all lines flush left)
  - A "Copy my choices" button that copies a plain-text summary like: `prefix=[tutor] scheme=cyan sep=— layout=indented`.
  - No external resources; one file; monospace font; works by double-clicking the file.

- [ ] **Step 2 (PAUSE): Open it for Arush and wait for his choices**

```bash
open tools/style-playground.html
```
Ask Arush to play with the controls and paste back the "Copy my choices" line. Do not proceed until he does.

- [ ] **Step 3: Apply the choices to `terminal-tutor.zsh`**

Map his choices onto the style block (ANSI escapes: dim gray `\e[2;37m`/`\e[2m`, cyan `\e[2;36m`+`\e[1;36m`, yellow `\e[2;33m`+`\e[1;33m`, green `\e[2;32m`+`\e[1;32m`). For "flat" layout change `tt_line`'s pad to always `""`. Update `TT_PREFIX` and `TT_SEP` to his picks.

- [ ] **Step 4: Show him the real thing (PAUSE)**

```bash
zsh -c 'source terminal-tutor.zsh; TUTOR_HOME=$(mktemp -d) zsh -c true; tt_preexec "git clone https://github.com/foo/bar"' 
```
Simpler reliable demo: `zsh -ic 'tutor reset >/dev/null; explain git clone https://github.com/foo/bar'` after Task 14's local install, or temporarily: `zsh -c 'TUTOR_HOME=$(mktemp -d) ; export TUTOR_HOME; source terminal-tutor.zsh; explain git clone https://github.com/foo/bar'`. Confirm he likes it in the real terminal; iterate Step 3 if not.

- [ ] **Step 5: Run tests (style change must not break them — tests override style vars), commit**

```bash
zsh tests/run.sh   # expected: failed: 0
git add tools/style-playground.html terminal-tutor.zsh
git commit -m "feat: visual style chosen via playground"
```

---

### Task 13: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`** with exactly these sections (write the full prose, in plain English for a non-engineer; keep the structure):
  1. **What this is** — one paragraph + a fenced example of the teaching output for `git clone …` (match the chosen style, plain text).
  2. **Install (any Mac)** — the one-liner `curl -fsSL https://raw.githubusercontent.com/REPO_OWNER/terminal-tutor/main/install.sh | bash`, then "open a new Terminal window". Note what the installer does (downloads to `~/.terminal-tutor/app`, adds a marked block to `~/.zshrc`).
  3. **Uninstall** — `tutor uninstall` (or `bash ~/.terminal-tutor/app/uninstall.sh`).
  4. **Daily use** — table of: automatic first-time teaching, `explain <command>` (with the quoting tip for `|`), `tutor on/off/reset/status`.
  5. **Add a command to the dictionary** — show the file format with a tiny example, mention `tutor reset` is NOT needed (new files take effect in new Terminal windows).
  6. **Alternatives & further learning** — tldr pages (`brew install tlrc`), explainshell.com, Warp terminal, and asking an AI agent (e.g. Claude Code) to explain any command.
  7. **For developers** — `./install.sh --local`, `zsh tests/run.sh`, project layout in 6 lines.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: plain-English README"
```

---

### Task 14: GitHub repo + end-to-end install test

⚠️ PAUSE POINTS: needs Arush for GitHub login and a public/private decision.

- [ ] **Step 1: Ensure gh CLI exists and is authenticated**

```bash
command -v gh || brew install gh
gh auth status
```
If not authenticated (PAUSE): ask Arush to run `! gh auth login` in this session (choose GitHub.com → HTTPS → browser login) and wait.

- [ ] **Step 2 (PAUSE): Confirm with Arush that a PUBLIC repo is OK**

The one-line installer needs a public repo. Nothing personal is in it (his learned-commands file stays on his machine, only the plugin + dictionary are published). If he insists on private, the install one-liner changes to a `git clone` + `bash install.sh` two-step and Step 5 adapts.

- [ ] **Step 3: Create the repo and push**

```bash
gh repo create terminal-tutor --public --source . --push --description "zsh plugin that teaches you what your terminal commands mean as you type them"
```
Expected: repo URL printed; `git push` succeeds.

- [ ] **Step 4: Replace REPO_OWNER placeholders**

```bash
OWNER="$(gh api user --jq .login)"
sed -i '' "s/REPO_OWNER/$OWNER/g" install.sh README.md
git add install.sh README.md
git commit -m "chore: point installer at the real GitHub repo"
git push
```

- [ ] **Step 5: End-to-end test of the curl install in a sandbox**

```bash
SANDBOX="$(mktemp -d)"
touch "$SANDBOX/.zshrc"
TUTOR_HOME="$SANDBOX" TUTOR_ZSHRC="$SANDBOX/.zshrc" bash -c "$(curl -fsSL https://raw.githubusercontent.com/$OWNER/terminal-tutor/main/install.sh)"
grep -F "terminal-tutor" "$SANDBOX/.zshrc"            # expected: the marked block
ls "$SANDBOX/.terminal-tutor/app/terminal-tutor.zsh"  # expected: file exists
TUTOR_HOME="$SANDBOX" TUTOR_ZSHRC="$SANDBOX/.zshrc" bash "$SANDBOX/.terminal-tutor/app/uninstall.sh"
rm -rf "$SANDBOX"
```
Expected: install works from the public internet, uninstall round-trips.

---

### Task 15: Install for Arush on this Mac + live verification

⚠️ PAUSE POINT: final check is Arush typing in a real new Terminal window.

- [ ] **Step 1: Local (developer-mode) install**

```bash
./install.sh --local
tail -5 ~/.zshrc   # expected: the marked terminal-tutor block
```
(`--local` symlinks the OneDrive project folder, so future edits/pulls take effect without reinstalling.)

- [ ] **Step 2: Scripted smoke test of a fresh interactive shell**

```bash
zsh -ic 'tt_preexec "tar -xzvf archive.tar.gz"; tutor status' 2>&1 | head -10
```
Expected: tutor lines for `tar` and its flags, then a status line. If `tt_preexec` is not found, the `.zshrc` block did not load — debug before continuing.

- [ ] **Step 3 (PAUSE): Ask Arush to verify live**

Ask him to open a brand-new Terminal window and type `ls -la`, then `ls -la` again (silent the second time), then `explain ls -la`, then `tutor status`. Confirm the experience matches the spec.

- [ ] **Step 4: Final commit & push**

```bash
git add -A && git status --short   # expect nothing or only intended changes
git commit -m "chore: final polish after live verification" || true
git push
```

---

## Self-review (done at planning time)

- **Spec coverage:** first-time + new-flag teaching (T6/T7), explain (T8), tutor incl. uninstall (T8/T11), pipelines/operators (T2/T5), unknown commands one-time note (T6/T7), ~95-command dictionary + `_operators` (T5/T9/T10), seen-file + state (T1/T5/T8), installer/uninstaller idempotent + marked block (T11), GitHub one-liner (T14), playground-chosen style (T12), README with alternatives (T13), error-guarded hook (T8), tests for parser/dict/seen/installer round-trip (T2–T11). URL-arg explanation from spec example (T6).
- **Known judgment calls:** `explain` does not mark things as seen (spec silent on it); unknown flags are skipped in automatic mode, labelled "(no entry)" in explain mode; operators dedupe within one line.
- **Type consistency check:** seen-key formats are used identically in T6 code, T7 tests, and T8 (`unknown:<cmd>`, `<cmd>`, `<cmd> <flag>`, `<cmd> <sub>`, `<cmd> arg:url`, `op:<op>`). Global arrays `TT_OUT`/`TT_NEWLY_SEEN`/`TT_SEGMENTS`/`TT_OPS`/`TT_TOKENS` are declared locally in the entry points (`tt_preexec`, `explain`, tests) and shared downward via zsh dynamic scoping.
