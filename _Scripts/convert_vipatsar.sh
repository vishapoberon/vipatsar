#!/bin/sh
# convert_vipatsar.sh: Convert old JSON vipakfiles to new plain-text format with
# proper file naming and versioning using convert_vipakfile.sh

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

# We assume that we're running inside vipatsar tree
for dir in $(find . -not -path '*/.git/*' -not -path '.' -type d) ;
do
  # The port/library name is derived from the directory
  port=${dir##./}
  pinfo "Working on ${port}"
  cd $dir
  paction "Converting ${port}.json"
  ../_Scripts/convert_vipakfile.sh -c "../${port}.json"
  pinfo "Conversion done"

  cd - >/dev/null || return
done

