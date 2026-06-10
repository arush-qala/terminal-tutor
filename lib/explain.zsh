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
