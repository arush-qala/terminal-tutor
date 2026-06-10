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
