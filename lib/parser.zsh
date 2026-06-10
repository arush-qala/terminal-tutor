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
