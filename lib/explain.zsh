# terminal-tutor explain engine: dictionary lookup, seen-state, line building.
# Callers must declare: local -a TT_OUT TT_NEWLY_SEEN  (tt_line/tt_mark/tt_seen use them).

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
        if [[ "$type" == summary && -n "$f2" ]]; then
          print -r -- "$f2${rest:+ $rest}"
          return 0
        fi
        ;;
      *)
        # non-summary lines need all three fields; incomplete lines are skipped
        if [[ "$f1" == "$type" && "$f2" == "$key" && -n "$rest" ]]; then
          print -r -- "$rest"
          return 0
        fi
        ;;
    esac
  done < "$file"
  return 1
}

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
        # path-like commands (./x, /bin/x, ../x) have no dictionary entries; skip
        [[ "$cmd" == */* ]] && { cmd=""; continue }
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
          # mark even if the file had no summary line, so it isn't re-checked every run
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
          if [[ "$mode" == all ]] || ! tt_seen "$cmd $val"; then
            if text="$(tt_dict_get "$cmd" sub "$val")"; then
              tt_line 1 "$val" "$text"
              [[ "$mode" == new ]] && tt_mark "$cmd $val"
              continue
            fi
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
