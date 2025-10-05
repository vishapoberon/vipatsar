#!/bin/sh
# convert_vipakfile.sh: Convert JSON vipakfile to plain-text .vipakfile format


PROGNAME=${0##*/}
VERSION="0.1.0"

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
Usage: $PROGNAME [-o <output_file> | -c] [-f] [--verbose] <input_json_file>
  Convert JSON vipakfile to new plain-text .vipakfile format.
  -o <output_file>  Write to specified file (default: stdout)
  -c                Write to <package>-<version>.vipakfile
  -f                Force overwrite of existing output file
  --verbose         Print debug information about extracted fields
EOF
  exit 0
}

command -v jq >/dev/null 2>&1 || perror "jq is required but not found"
command -v sed >/dev/null 2>&1 || perror "sed is required but not found"

output_mode="stdout"
output_file=""
input_file=""
force_overwrite=""
verbose=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      [ $# -lt 2 ] && perror "Option -o requires an output file"
      output_mode="file"
      output_file="$2"
      shift 2
      ;;
    -c)
      output_mode="versioned"
      shift
      ;;
    -f)
      force_overwrite=1
      shift
      ;;
    --verbose)
      verbose=1
      shift
      ;;
    -*)
      perror "Unknown option: $1"
      ;;
    *)
      [ -n "$input_file" ] && perror "Only one input file allowed"
      input_file="$1"
      shift
      ;;
  esac
done

[ -z "$input_file" ] && usage
[ -f "$input_file" ] || perror "Input file '$input_file' not found"
[ -r "$input_file" ] || perror "Input file '$input_file' is not readable"

jq -e . "$input_file" >/dev/null 2>&1 || perror "Invalid JSON in $input_file"

paction "Parsing $input_file"
name=$(jq -r '.package // ""' "$input_file")
version=$(jq -r '.version // ""' "$input_file")
author=$(jq -r '.author // ""' "$input_file")
license=$(jq -r '.license // ""' "$input_file")

[ -z "$name" ] && perror "package field is required"
[ -z "$version" ] && perror "version field is required"

# Extract Remote (handle git and https)
remote_type=$(jq -r '.remote.type // ""' "$input_file")
remote=""
case "$remote_type" in
  git)
    remote_url=$(jq -r '.remote.url // .remote.path // ""' "$input_file")
    remote_tag=$(jq -r '.remote.tag // ""' "$input_file")
    if [ -z "$remote_url" ]; then
      perror "remote.url or remote.path required for remote.type=git"
    fi
    remote="git $remote_url"
    [ -n "$remote_tag" ] && remote="$remote $remote_tag"
    ;;
  https)
    # Extract remote.files as raw data
    remote_files=$(jq -r '.remote.files // [] | map(
      [.url, .authtype // "None", .authcredentials.user // "", .authcredentials.password // "", .md5 // ""] | join("\t")
    ) | join("\n")' "$input_file") || {
      perror "Failed to process remote.files in $input_file"
      exit 1
    }
    if [ -z "$remote_files" ]; then
      perror "remote.files required for remote.type=https"
    fi
    # Process each file entry in shell
    remote_files_out=""
    IFS='
'
    for file in $remote_files; do
      url=$(echo "$file" | cut -f1)
      authtype=$(echo "$file" | cut -f2)
      user=$(echo "$file" | cut -f3)
      password=$(echo "$file" | cut -f4)
      md5=$(echo "$file" | cut -f5)
      if [ "$authtype" = "BasicAuth" ]; then
        if [ -z "$user" ] || [ -z "$password" ]; then
          perror "Missing authcredentials.user or authcredentials.password for BasicAuth in $input_file"
        fi
        # Insert user:password@ after protocol
        auth_url=$(echo "$url" | sed -E "s,^(https?://),\1$user:$password@,")
        entry="$auth_url md5,$md5"
      else
        entry="$url md5,$md5"
      fi
      if [ -z "$remote_files_out" ]; then
        remote_files_out="$entry"
      else
        remote_files_out="$remote_files_out;$entry"
      fi
    done
    unset IFS
    remote="https $remote_files_out"
    ;;
  "")
    : # Empty remote is valid
    ;;
  *)
    perror "Unsupported remote.type: $remote_type. Only 'git' or 'https' allowed"
    ;;
esac

deps=$(jq -r 'if .dependencies then .dependencies | to_entries | map("\(.key):\(.value)") | join(" ") else "" end' "$input_file")
build=$(jq -r '.build // [] | map(.command + " " + .file) | join(";")' "$input_file")
[ "$build" = "null" ] && build=""

run=""
main=""
test_run=""
test_main=""
test_cmd=""

[ -n "$verbose" ] && {
  pinfo "Extracted fields:"
  pinfo "  NAME=$name"
  pinfo "  VERSION=$version"
  pinfo "  AUTHOR=$author"
  pinfo "  LICENSE=$license"
  pinfo "  REMOTE=$remote"
  pinfo "  DEPS=$deps"
  pinfo "  BUILD=$build"
  pinfo "  RUN=$run"
  pinfo "  MAIN=$main"
  pinfo "  TEST_RUN=$test_run"
  pinfo "  TEST_MAIN=$test_main"
  pinfo "  TEST=$test_cmd"
}

vipakfile_content=$(cat <<EOF
NAME      = $name
VERSION   = $version

AUTHOR    = $author
LICENSE   = $license

REMOTE    = $remote

DEPS      = $deps

RUN       = $run
MAIN      = $main
BUILD     = $build

TEST_RUN  = $test_run
TEST_MAIN = $test_main
TEST      = $test_cmd
EOF
)

case "$output_mode" in
  stdout)
    paction "Writing to stdout"
    printf "%s\n" "$vipakfile_content"
    ;;
  file)
    [ -z "$force_overwrite" ] && [ -f "$output_file" ] && perror "Output file '$output_file' already exists"
    paction "Writing $output_file"
    printf "%s\n" "$vipakfile_content" > "$output_file" 2>/dev/null || perror "Failed to write to '$output_file'"
    pinfo "Conversion complete: $output_file"
    ;;
  versioned)
    output_file="$name-$version.vipakfile"
    [ -z "$force_overwrite" ] && [ -f "$output_file" ] && perror "Output file '$output_file' already exists"
    paction "Writing $output_file"
    printf "%s\n" "$vipakfile_content" > "$output_file" 2>/dev/null || perror "Failed to write to '$output_file'"
    pinfo "Conversion complete: $output_file"
    ;;
esac
