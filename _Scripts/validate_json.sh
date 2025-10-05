#!/bin/sh
# validate_json.sh: Validate JSON vipakfiles


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
  Validate JSON vipakfiles.
  --all    Validate all .json files in current directory
  file     Validate specified JSON files
EOF
  exit 0
}

command -v jq >/dev/null 2>&1 || perror "jq is required but not found"

validate_json() {
  json="$1"
  errors=0
  if ! jq -e . "$json" >/dev/null 2>/dev/null; then
    perror "$json is not valid JSON"
    errors=$((errors + 1))
  fi
  if ! jq -e '.package | type == "string" and length > 0' "$json" >/dev/null 2>/dev/null; then
    perror "$json missing or invalid package field"
    errors=$((errors + 1))
  fi
  if ! jq -e '.version | type == "string" and length > 0' "$json" >/dev/null 2>/dev/null; then
    perror "$json missing or invalid version field"
    errors=$((errors + 1))
  fi
  if ! jq -e '.author | type == "string"' "$json" >/dev/null 2>/dev/null; then
    perror "$json invalid author field (must be string)"
    errors=$((errors + 1))
  fi
  if ! jq -e '.license | type == "string"' "$json" >/dev/null 2>/dev/null; then
    perror "$json invalid license field (must be string)"
    errors=$((errors + 1))
  fi
  if jq -e '.remote | type == "object"' "$json" >/dev/null 2>/dev/null; then
    if ! jq -e '.remote.type | type == "string" and (. == "" or . == "git" or . == "https")' "$json" >/dev/null 2>/dev/null; then
      perror "$json invalid remote.type (must be empty, 'git', or 'https')"
      errors=$((errors + 1))
    fi
    if jq -e '.remote.type == "git"' "$json" >/dev/null 2>/dev/null; then
      if ! jq -e '.remote.url // .remote.path | type == "string" and length > 0' "$json" >/dev/null 2>/dev/null; then
        perror "$json with remote.type=git missing or invalid remote.url or remote.path"
        errors=$((errors + 1))
      fi
      if jq -e '.remote.tag | type != "string"' "$json" >/dev/null 2>/dev/null; then
        perror "$json invalid remote.tag (must be string)"
        errors=$((errors + 1))
      fi
    fi
    if jq -e '.remote.type == "https"' "$json" >/dev/null 2>/dev/null; then
      if ! jq -e '.remote.files | type == "array" and length > 0' "$json" >/dev/null 2>/dev/null; then
        perror "$json with remote.type=https missing or empty remote.files array"
        errors=$((errors + 1))
      fi
      if ! jq -e '.remote.files[] | select(type == "object" and (.url | test("^(http|https)://") and .md5 | test("^[0-9a-f]{32}$")) and (.authtype != "BasicAuth" or (.authcredentials.user | type == "string" and length > 0 and .authcredentials.password | type == "string" and length > 0)))' "$json" >/dev/null 2>/dev/null; then
        jq -r '.remote.files[] | select(type != "object" or (.url | not or (.url | test("^(http|https)://") | not) or (.md5 | not or (.md5 | test("^[0-9a-f]{32}$") | not)) or (.authtype == "BasicAuth" and (.authcredentials.user | not or (.authcredentials.user | type != "string" or length == 0) or .authcredentials.password | not or (.authcredentials.password | type != "string" or length == 0)))) | .url // "missing"' "$json" 2>/dev/null | while read -r url; do
          perror "$json has invalid remote.files entry (url: $url, must be object with valid URL, 32-char MD5, and for BasicAuth, non-empty user/password)"
          errors=$((errors + 1))
        done
        if [ $? -ne 0 ]; then
          perror "$json remote.files validation failed due to jq error"
          errors=$((errors + 1))
        fi
      fi
    fi
  fi
  if jq -e '.dependencies | type != "object"' "$json" >/dev/null 2>/dev/null; then
    perror "$json invalid dependencies field (must be object)"
    errors=$((errors + 1))
  fi
  if ! jq -e '.build | type == "array"' "$json" >/dev/null 2>/dev/null; then
    perror "$json invalid build field (must be array)"
    errors=$((errors + 1))
  fi
  if ! jq -e '.build[] | select(type == "object" and .command | type == "string" and length > 0 and .file | type == "string" and length > 0)' "$json" >/dev/null 2>/dev/null; then
    jq -r '.build[] | select(type != "object" or (.command | not or (.command | type != "string" or length == 0) or .file | not or (.file | type != "string" or length == 0))) | .file // "missing"' "$json" 2>/dev/null | while read -r file; do
      perror "$json has invalid build entry (file: $file, must be object with non-empty command and file)"
      errors=$((errors + 1))
    done
    if [ $? -ne 0 ]; then
      perror "$json build validation failed due to jq error"
      errors=$((errors + 1))
    fi
  fi
  [ $errors -eq 0 ] && pinfo "$json is valid"
  return $errors
}

errors=0
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
  paction "Validating $file"
  validate_json "$file"
  [ $? -ne 0 ] && errors=$((errors + 1))
done

if [ $errors -eq 0 ]; then
  pinfo "All JSON files validated successfully"
  exit 0
else
  perror "Validation failed with $errors error(s)"
  exit 1
fi
