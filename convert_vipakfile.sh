#!/bin/sh

# convert_vipakfile.sh: Convert old JSON vipakfile to new plain-text format

# Program name and version
PROGNAME=${0##*/}
VERSION="0.1.0"

# Colors for output
COLOUR_SET_R="\033[0;31m"
COLOUR_SET_G="\033[0;32m"
COLOUR_SET_B="\033[0;34m"
COLOUR_END="\033[0m"

# Error, info, and action print functions
perror() {
  printf "${COLOUR_SET_R}[-] ${COLOUR_END}%s\n" "$@" >&2
  exit 1
}

pinfo() {
  printf "${COLOUR_SET_B}[+] ${COLOUR_END}%s\n" "$@" >&2
}

paction() {
  printf "${COLOUR_SET_G}[*] ${COLOUR_END}%s\n" "$@" >&2
}

# Usage message
usage() {
  cat <<EOF
Usage: $PROGNAME [-o <output_file> | -c] [-f] [--verbose] <input_json_file>
  Convert old JSON vipakfile to new plain-text format.
  -o <output_file>  Write to specified file (default: stdout)
  -c                Write to <Package>-<Version>.vipakfile
  -f                Force overwrite of existing output file
  --verbose         Print debug information about extracted fields
EOF
  exit 0
}

# Check dependencies
command -v jq >/dev/null 2>&1 || perror "jq is required but not found"

# Parse arguments
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

# Validate JSON
jq -e . "$input_file" >/dev/null 2>&1 || perror "Invalid JSON in $input_file"

# Extract fields using jq
paction "Parsing $input_file"
name=$(jq -r '.Package // ""' "$input_file")
version=$(jq -r '.Version // ""' "$input_file")
author=$(jq -r '.Author // ""' "$input_file")
license=$(jq -r '.License // ""' "$input_file")

# Validate required fields
[ -z "$name" ] && perror "Package name is required"
[ -z "$version" ] && perror "Version is required"

# Extract Remote (type, path, tag)
remote_type=$(jq -r '.Remote.type // ""' "$input_file")
remote_path=$(jq -r '.Remote.path // ""' "$input_file")
remote_tag=$(jq -r '.Remote.tag // ""' "$input_file")
remote=""
if [ -n "$remote_type" ] && [ -n "$remote_path" ] && [ -n "$remote_tag" ]; then
  remote="$remote_type $remote_path $remote_tag"
fi

# Extract Dependencies as space-separated list
deps=$(jq -r 'if .Dependencies then .Dependencies | to_entries | map("\(.key):\(.value)") | join(" ") else "" end' "$input_file")

# Extract Build commands as semicolon-separated list
build=$(jq -r '.Build | map(.command + " " + .file) | join(";")' "$input_file")
[ "$build" = "null" ] && build=""

# Default empty fields
run=""
main=""
test_run=""
test_main=""
test_cmd=""

# Verbose output
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

# Generate vipakfile content
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

# Handle output
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
