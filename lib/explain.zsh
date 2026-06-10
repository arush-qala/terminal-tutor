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
