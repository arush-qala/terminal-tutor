# terminal-tutor parser: pure functions, no file or terminal I/O.

# tt_split <command line>
# Sets: TT_SEGMENTS - array; each element = one command's words joined by \x1f
#       TT_OPS      - array of shell operators seen (deduped, in order)
# Redirection operators (> >> < etc.) consume the word after them (the file),
# so filenames are never mistaken for commands.
tt_split() {
  emulate -L zsh
  local -a words cur
  local w nxt skip_next=0
  TT_SEGMENTS=() TT_OPS=()
  words=(${(z)1})
  local idx
  for (( idx=1; idx <= ${#words}; idx++ )); do
    w="${words[idx]}"
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
      '>&'|[0-9]'>&')
        # zsh lexes "2>&1" as two tokens: "2>&" and "1"
        nxt="${words[idx+1]:-}"
        if [[ "$nxt" == [0-9] ]]; then
          local combined="${w}${nxt}"
          (( ${TT_OPS[(Ie)$combined]} )) || TT_OPS+=("$combined")
          (( idx++ ))   # consume the digit
        else
          (( ${TT_OPS[(Ie)$w]} )) || TT_OPS+=("$w")
          skip_next=1   # csh-style ">& file" — consume the filename
        fi
        ;;
      '<<'|'<<-'|'<<<')
        (( ${TT_OPS[(Ie)$w]} )) || TT_OPS+=("$w")
        skip_next=1   # consume the heredoc marker / herestring word
        ;;
      *) cur+=("$w") ;;
    esac
  done
  (( ${#cur} )) && TT_SEGMENTS+=("${(pj:\x1f:)cur}")
  return 0
}

# tt_tokenize <segment (words joined by \x1f)>
# Sets TT_TOKENS - array of "type:value" with type: cmd | flag | word | arg
tt_tokenize() {
  emulate -L zsh
  local -a words
  words=("${(ps:\x1f:)1}")
  TT_TOKENS=()
  local w i expecting_cmd=1 after_dashdash=0
  for w in "${words[@]}"; do
    if (( expecting_cmd )) && [[ "$w" != -* ]]; then
      if [[ "$w" == *=* ]]; then
        TT_TOKENS+=("word:$w")   # env-var assignment, not a command
      else
        TT_TOKENS+=("cmd:$w")
        [[ "$w" == sudo || "$w" == env ]] || expecting_cmd=0
      fi
      continue
    fi
    # After --, nothing is classified as a flag
    if (( after_dashdash )); then
      TT_TOKENS+=("word:$w")
      continue
    fi
    case "$w" in
      --) TT_TOKENS+=("arg:--"); after_dashdash=1 ;;
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
