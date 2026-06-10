#!/bin/bash
# terminal-tutor uninstaller. Removes the ~/.zshrc block and all state. Safe to run twice.
set -uo pipefail

TT_HOME="${TUTOR_HOME:-$HOME}"
ZSHRC="${TUTOR_ZSHRC:-$TT_HOME/.zshrc}"

# require BOTH markers: an unterminated sed range would delete to end of file
if [[ -f "$ZSHRC" ]] \
  && grep -qF "# >>> terminal-tutor >>>" "$ZSHRC" \
  && grep -qF "# <<< terminal-tutor <<<" "$ZSHRC"; then
  sed -i '' '/# >>> terminal-tutor >>>/,/# <<< terminal-tutor <<</d' "$ZSHRC"
  # the installer added a blank line before the block; drop a single trailing blank line
  if [[ -z "$(tail -n 1 "$ZSHRC")" ]]; then
    sed -i '' -e '$ d' "$ZSHRC"
  fi
fi

rm -rf "$TT_HOME/.terminal-tutor"

echo "terminal-tutor removed. Open a new Terminal window to finish."
