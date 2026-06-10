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
