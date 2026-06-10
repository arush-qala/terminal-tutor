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

# --- Style (chosen by Arush via tools/style-playground.html:
#     prefix=[tutor] scheme=yellow sep=— layout=indented) ---
typeset -g TT_PREFIX="[tutor]"
typeset -g TT_SEP="—"
typeset -g TT_C_PREFIX=$'\e[2;33m'   # dim yellow
typeset -g TT_C_TERM=$'\e[1;33m'     # bright yellow
typeset -g TT_C_TEXT=$'\e[2m'        # dim
typeset -g TT_C_RESET=$'\e[0m'

source "$TT_DIR/lib/parser.zsh"
source "$TT_DIR/lib/explain.zsh"

# --- the hook: runs just before every command; must never break anything ---
tt_preexec() {
  setopt localoptions noerrexit
  {
    local tt_state=""
    [[ -r "$TT_STATE_FILE" ]] && read -r tt_state < "$TT_STATE_FILE"
    [[ "$tt_state" == off ]] && return 0
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

autoload -Uz add-zsh-hook 2>/dev/null; add-zsh-hook preexec tt_preexec 2>/dev/null

# --- explain: full breakdown on demand, e.g.  explain ls -la ---
explain() {
  emulate -L zsh
  if (( $# == 0 )); then
    print "Usage: explain <command>     e.g.  explain ls -la"
    print "Tip: put quotes around commands with | or > :  explain 'cat log | grep error'"
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
      mkdir -p "$TT_STATE_DIR" 2>/dev/null
      print on > "$TT_STATE_FILE" 2>/dev/null
      print "terminal-tutor: ON - new commands will be explained." ;;
    off)
      mkdir -p "$TT_STATE_DIR" 2>/dev/null
      print off > "$TT_STATE_FILE" 2>/dev/null
      print "terminal-tutor: OFF - run 'tutor on' to resume." ;;
    reset)
      mkdir -p "$TT_STATE_DIR" 2>/dev/null
      : > "$TT_SEEN_FILE" 2>/dev/null
      print "terminal-tutor: memory cleared - everything will be taught again." ;;
    status)
      local state="on"
      [[ -r "$TT_STATE_FILE" ]] && read -r state < "$TT_STATE_FILE"; [[ -n "$state" ]] || state=on
      local learned=0
      [[ -r "$TT_SEEN_FILE" ]] && learned="$(grep -c '' "$TT_SEEN_FILE")"
      local -a dfiles
      setopt localoptions extendedglob
      dfiles=("$TT_DICT_DIR"/^_*(N))
      print "terminal-tutor: $state | things learned: $learned | commands in dictionary: ${#dfiles}" ;;
    uninstall)
      "$TT_DIR/uninstall.sh" ;;
    *)
      print "Usage: tutor on | off | reset | status | uninstall" ;;
  esac
}
