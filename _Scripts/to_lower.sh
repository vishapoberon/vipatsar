#!/bin/sh
# to_lower.sh: Convert JSON keys to lowercase, preserving dependencies subkeys


PROGNAME=${0##*/}

COLOUR_SET_R="\033[0;31m"
COLOUR_SET_G="\033[0;32m"
COLOUR_SET_B="\033[0;34m"
COLOUR_END="\033[0m"

perror() {
  printf "${COLOUR_SET_R}[-] ${COLOUR_END}%s\n" "$@" >&2
  exit 1
}

pinfo() {
  printf "${COLOUR_SET_B}[*] ${COLOUR_END}%s\n" "$@" >&2
}

paction() {
  printf "${COLOUR_SET_G}[+] ${COLOUR_END}%s\n" "$@" >&2
}

usage() {
  cat <<EOF
Usage: $PROGNAME [--all] [file ...]
  Convert JSON keys to lowercase, preserving dependencies subkeys.
  --all    Process all .json files in current directory
  file     Process specified JSON files
EOF
  exit 0
}

command -v jq >/dev/null 2>&1 || perror "jq is required but not found"

if [ $# -eq 0 ]; then
  usage
fi

if [ "$1" = "--all" ]; then
  files=$(ls *.json 2>/dev/null)
  [ -z "$files" ] && perror "No JSON files found in current directory"
else
  files="$*"
  for file in $files; do
    [ -f "$file" ] || perror "File $file not found"
    case "$file" in
      *.json) : ;;
      *) perror "File $file is not a .json file" ;;
    esac
  done
fi

for file in $files; do
  [ -r "$file" ] || perror "File $file is not readable"
  paction "Converting keys to lowercase in $file"
  tmpfile=$(mktemp)
  jq '
    def to_lower:
      if type == "object" then
        with_entries(
          .key |= (if . == "dependencies" then . else ascii_downcase end)
        ) | map_values(to_lower)
      elif type == "array" then
        map(to_lower)
      else
        .
      end;
    to_lower
  ' "$file" > "$tmpfile" 2>/dev/null || {
    rm -f "$tmpfile"
    perror "Failed to process $file with jq"
  }
  mv "$tmpfile" "$file" || perror "Failed to overwrite $file"
  pinfo "Processed $file"
done

pinfo "All files processed successfully"
