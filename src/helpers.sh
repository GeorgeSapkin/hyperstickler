#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-only

color_out() {
	printf "\e[0;$1m%s%s\e[0m\n" "${PKG_NAME:+$PKG_NAME: }" "$2"
}

info() {
	color_out 36 "$1"
}

err() {
	color_out 31 "$1"
}

warn() {
	color_out 33 "$1"
}

err_die() {
	err "$1"
	exit 1
}

# Prints the string and colors the part after the given length in red
split_fail() {
	printf "$3%s\e[1;31m%s\e[0m\n" "${2:0:$1}" "${2:$1}"
}

# Prints the string and colors the part between $1 and $2 in yellow, after $2 in
# red
split_fail_ex() {
	printf "$4%s\e[1;33m%s\e[1;31m%s\e[0m\n" "${3:0:$1}" "${3:$1:$(($2 - $1))}" "${3:$2}"
}

# Prints `[$2] $3` with status colored according to `$1`
status() {
	printf "%s[\e[1;$1m%s\e[0m] %s\n" "${PKG_NAME:+$PKG_NAME: }" "$2" "$3"
}

# Prints `[pass] $1` with green pass (or blue on GitHub)
status_pass() {
	status 32 pass "$1"
}

# Prints `[warn] $1` with yellow warn
status_warn() {
	status 33 warn "$1"
}

# Prints `[fail] $1` with red fail
status_fail() {
	status 31 fail "$1"
}

# Prints `[skip] $1` with default-colored skip
status_skip() {
	status 39 skip "$1"
}

# Escapes special characters in the given text to be safe for inclusion in LaTeX
# output.
escape_latex() {
	local text="$1"

	# Placeholders for characters that need special handling
	local bs='LATEXESCAPEBACKSLASH'
	local crt='LATEXESCAPECARET'
	local rcb='LATEXESCAPERCB'
	local tld='LATEXESCAPETILDE'

	# Replacement strings (stored in variables to avoid bash parsing issues with
	# } in replacement strings)
	local r_bs='\textbackslash{}'
	local r_crt='\textasciicircum{}'
	local r_rcb='\}'
	local r_tld='\textasciitilde{}'

	# First, replace characters that need placeholders
	text="${text//\\/$bs}"
	text="${text//^/$crt}"
	text="${text//\}/$rcb}"
	text="${text//\~/$tld}"

	# Escape simple characters
	text="${text//_/\\_}"
	text="${text//\$/\\$}"
	text="${text//&/\\&}"
	text="${text//%/\\%}"
	text="${text//#/\\#}"
	text="${text//\{/\\{}"

	# Replace placeholders with actual LaTeX commands
	text="${text//$bs/$r_bs}"
	text="${text//$crt/$r_crt}"
	text="${text//$rcb/$r_rcb}"
	text="${text//$tld/$r_tld}"

	echo "$text"
}
