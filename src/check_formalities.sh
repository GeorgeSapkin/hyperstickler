#!/bin/bash
#
# Copyright (C) 2025, George Sapkin
#
# SPDX-License-Identifier: GPL-2.0-only

# Based on https://openwrt.org/submitting-patches#submission_guidelines
# Hard limit is arbitrary
MAX_SUBJECT_LEN_HARD=${MAX_SUBJECT_LEN_HARD:-60}
MAX_SUBJECT_LEN_SOFT=${MAX_SUBJECT_LEN_SOFT:-50}
MAX_BODY_LINE_LEN=${MAX_BODY_LINE_LEN:-75}

CHECK_SIGNOFF=${CHECK_SIGNOFF:-false}
EXCLUDE_DEPENDABOT=${EXCLUDE_DEPENDABOT:-false}
EXCLUDE_WEBLATE=${EXCLUDE_WEBLATE:-false}
SHOW_LEGEND=${SHOW_LEGEND:-true}

FEEDBACK_URL=${FEEDBACK_URL:-}

if [ "$MAX_SUBJECT_LEN_SOFT" -gt "$MAX_SUBJECT_LEN_HARD" ]; then
	echo "MAX_SUBJECT_LEN_SOFT ($MAX_SUBJECT_LEN_SOFT) cannot be larger than MAX_SUBJECT_LEN_HARD ($MAX_SUBJECT_LEN_HARD)" >&2
	exit 1
fi

INDENT_MD='    '
INDENT_TERM='       '

DEPENDABOT_EMAIL='dependabot[bot]@users.noreply.github.com'
GITHUB_NOREPLY_EMAIL='@users.noreply.github.com'
WEBLATE_EMAIL='hosted@weblate.org'

EMOJI_WARN=':large_orange_diamond:'
EMOJI_FAIL=':x:'

PREFIX_REGEX='^([0-9A-Za-z,+/._-]+: )+'

declare -A ARITY

RES_FAIL=3
RES_SKIP=1
RES_WARN=2

FAIL=0

# Email parts of authors for which most checks will be skipped
EXCEPTION_EMAILS=()
EXCEPTION_NAMES=()

# Used to communicate skipping reasons between checks without explicitly passing
# it around
SKIP_REASONS=()

# Use these global vars to improve header creation readability
COMMIT=""
HEADER_SET=0

REPO_PATH=${1:+-C "$1"}
# shellcheck disable=SC2206
REPO_PATH=($REPO_PATH)

# Delimiters for git commit formatting
_F=$'\xf0'
_R=$'\xfa'

# Fetch all data from a commit in one go
GIT_HEADER='%C(yellow)commit %H%n%C(reset)Author: %an <%ae>%nCommit: %cn <%ce>%n%n%w(0,4,4)%B'
GIT_VARS="%H${_F}%aN${_F}%aE${_F}%cN${_F}%cE${_F}%s${_F}%b${_F}Signed-off-by: %aN <%aE>${_F}%P"
GIT_FORMAT="${_F}${GIT_HEADER}${_F}${GIT_VARS}${_R}"

ACTION_PATH=${ACTION_PATH:+"$ACTION_PATH/src"}
ACTION_PATH=${ACTION_PATH:-$(dirname "$(readlink -f "$0")")}
source "$ACTION_PATH/helpers.sh"

feedback() {
	cat <<-EOF
	Something broken? Consider providing feedback:
	${FEEDBACK_URL}

	EOF
}

legend() {
	info 'Legend:'
	status_pass 'Check passed'
	status_warn "Check passed with a warning and won't fail the job"
	status_fail 'Check failed and will fail the job'
	status_skip "Check skipped, due to another check or configuration and won't affect the job"
	echo
}

# output_xxx write to GitHub Actions output to be later posted to a PR
# status_xxx write to terminal

output() {
	[ -f "$GITHUB_OUTPUT" ] || return

	echo "$1" >> "$GITHUB_OUTPUT"
}

output_header() {
	[ "$HEADER_SET" = 0 ] || return

	[ -f "$GITHUB_OUTPUT" ] || return

	cat >> "$GITHUB_OUTPUT" <<-HEADER

	### Commit $COMMIT

	HEADER

	HEADER_SET=1
}

output_raw() {
	output "$INDENT_MD$1"
	echo "$INDENT_TERM$1"
}

output_details() {
	local actual="${1:-}"
	local expected="${2:-}"

	if [ -n "$actual" ]; then
		output_raw "Actual: $actual"
	fi

	if [ -n "$expected" ]; then
		output_raw "Expected: $expected"
	fi
}

output_pass() {
	local msg="$1"
	local reason="${2:-}"

	# Don't actually output anything to actions output
	status_pass "$msg"
	if [ -n "$reason" ]; then
		echo "${INDENT_TERM}Reason: $reason"
	fi
}

output_warn() {
	local msg="$1"
	local actual="${2:-}"
	local expected="${3:-}"

	output_header
	output "- $EMOJI_WARN $msg"
	status_warn "$msg"
	output_details "$actual" "$expected"
}

output_fail() {
	local msg="$1"
	local actual="${2:-}"
	local expected="${3:-}"

	output_header
	output "- $EMOJI_FAIL $msg"
	status_fail "$msg"
	output_details "$actual" "$expected"

	FAIL=1
}

output_skip() {
	local msg="$1"
	local reason="${2:-}"

	# Don't actually output anything to actions output
	status_skip "$msg"
	if [ -n "$reason" ]; then
		echo "${INDENT_TERM}Reason: $reason"
	fi
}

output_split_fail() {
	split_fail "$1" "$2" "${INDENT_TERM}"
	[ -f "$GITHUB_OUTPUT" ] || return
	printf "${INDENT_MD}\$\\\textsf{%s\\color{red}{%s}}\$\n" \
		"${2:0:$1}" "${2:$1}" >> "$GITHUB_OUTPUT"
}

output_split_fail_ex() {
	split_fail_ex "$1" "$2" "$3" "${INDENT_TERM}"
	[ -f "$GITHUB_OUTPUT" ] || return
	printf "${INDENT_MD}\$\\\textsf{%s\\color{yellow}{%s}\\color{red}{%s}}\$\n" \
		"${3:0:$1}" "${3:$1:$(($2 - $1))}" "${3:$2}" >> "$GITHUB_OUTPUT"
}

# shellcheck disable=SC2329
check_signoff()        { [ "$CHECK_SIGNOFF" = 'true' ]; }
# shellcheck disable=SC2329
do_not_check_signoff() { ! check_signoff; }
# shellcheck disable=SC2329
ends_with_period()     { [[ "$1" =~ \.$ ]]; }
exclude_dependabot()   { [ "$EXCLUDE_DEPENDABOT" = 'true' ]; }
exclude_weblate()      { [ "$EXCLUDE_WEBLATE" = 'true' ]; }
has_base()             { [ -n "$BASE_BRANCH" ]; }
# shellcheck disable=SC2329
has_no_prefix()        { [[ ! "$1" =~ $PREFIX_REGEX ]]; }
is_fail()              { [ "$1" = "$RES_FAIL" ]; }
# shellcheck disable=SC2329
is_first_word_caps()   { [[ "$1" =~ ${PREFIX_REGEX}[A-Z] ]]; }
# shellcheck disable=SC2329
is_github_noreply()    { [[ "${1,,}" == *"${GITHUB_NOREPLY_EMAIL,,}"* ]]; }
# shellcheck disable=SC2329
is_gt()                { [ "$1" -gt "$2" ]; }
# shellcheck disable=SC2329
is_main_branch()       { [[ "$1" =~ ^(origin/)?(main|master)$ ]]; }
# shellcheck disable=SC2329
is_merge()             { [[ "$1" == *" "* ]]; }
# shellcheck disable=SC2329
is_not_alias()         { [[ ! "$1" =~ [^[:space:]] ]]; }
# shellcheck disable=SC2329
is_not_name()          { [[ ! "$1" =~ [^[:space:]]+[[:space:]][^[:space:]]+ ]]; }
is_revert()            { [[ "$1" == "Revert "* ]]; }
is_warn()              { [ "$1" = "$RES_WARN" ]; }
# shellcheck disable=SC2329
omits()                { [[ "$1" != *"$2"* ]]; }
show_legend()          { [ "$SHOW_LEGEND" = 'true' ]; }
show_feedback()        { [ -n "$FEEDBACK_URL" ]; }
# shellcheck disable=SC2329
starts_with_space()    { [[ "$1" =~ ^[[:space:]] ]]; }

# shellcheck disable=SC2329
is_body_empty()        {
	local line
	while IFS= read -r line; do
		[[ "$line" == *"Signed-off-by:"* ]] && continue
		[[ "$line" =~ [^[:space:]] ]] && return 1
	done <<< "$1"
	return 0
}

have_exceptions() { [ "${#EXCEPTION_NAMES[@]}" -gt 0 ]; }

push_exception() {
	EXCEPTION_NAMES+=("$1")
	EXCEPTION_EMAILS+=("$2")
}

is_exception() {
	local email="$1"
	if [ -z "$email" ]; then
		return 1
	fi

	for idx in "${!EXCEPTION_EMAILS[@]}"; do
		if [[ "${email,,}" == *"${EXCEPTION_EMAILS[$idx],,}"* ]]; then
			echo "${EXCEPTION_NAMES[$idx]}"
			return 0
		fi
	done
	return 1
}

check_exceptions() {
	exclude_dependabot && push_exception 'dependabot' "$DEPENDABOT_EMAIL"
	exclude_weblate && push_exception 'weblate' "$WEBLATE_EMAIL"

	if have_exceptions; then
		warn "Enabled exceptions: ${EXCEPTION_NAMES[*]}"
	else
		echo 'Enabled exceptions: none'
	fi
	echo
}

have_skip_reasons()    { [ "${#SKIP_REASONS[@]}" -gt 0 ]; }
is_skip_reason()       { have_skip_reasons && [ "${SKIP_REASONS[-1]}" = "$1" ]; }
peek_skip_reason()     { have_skip_reasons && echo "${SKIP_REASONS[-1]}"; }
pop_skip_reason()      { unset "SKIP_REASONS[-1]"; }
pop_if_skip_reason()   { is_skip_reason "$1" && pop_skip_reason; }
push_skip_reason()     { SKIP_REASONS+=("$1"); }

reset_skip_reasons() {
	local author_email="$1"
	local exception

	SKIP_REASONS=()
	exception="$(is_exception "$author_email")"
	# shellcheck disable=SC2181
	if [ $? = 0 ]; then
		push_skip_reason "authored by $exception"
	fi
}

get_arity() {
	local fn_name="$1"
	if [ -n "${ARITY[$fn_name]}" ]; then
		echo "${ARITY[$fn_name]}"
		return
	fi

	local fn_body
	fn_body=$(declare -f "$fn_name")

	# Count the highest number used in a positional parameter like $1, $2, etc.
	local arity=0
	while [[ "$fn_body" =~ \$\{?([0-9]+) ]]; do
		local val="${BASH_REMATCH[1]}"
		[ "$val" -gt "$arity" ] && arity="$val"
		fn_body="${fn_body#*"${BASH_REMATCH[0]}"}"
	done

	ARITY[$fn_name]=$arity
	echo "$arity"
}

# To prevent command injection from malicious commit data, instead of using
# `eval`, this takes a function name and arguments for conditions separately.
check() {
	local rule
	local pass_reason
	local fail_fn fail_args fail_actual fail_expected fail_set_skip
	local warn_fn warn_args warn_actual warn_expected
	local skip_fn skip_args
	local skip_reason
	local fn arity
	local flag fn_args
	local always=0

	while [ $# -gt 0 ]; do
		case "$1" in
			-rule)          rule="$2";          shift ;;
			-pass-reason)   pass_reason="$2";   shift ;;
			-always)        always=1;                 ;;
			-skip-reason)   skip_reason="$2";   shift ;;
			-fail-actual)   fail_actual="$2";   shift ;;
			-fail-expected) fail_expected="$2"; shift ;;
			-fail-set-skip) fail_set_skip="$2"; shift ;;
			-warn-actual)   warn_actual="$2";   shift ;;
			-warn-expected) warn_expected="$2"; shift ;;

			-skip-if|-fail-if|-warn-if)
				flag="${1#-}"
				flag="${flag%-if}"
				if ! declare -F "$2" >/dev/null; then
					err_die "Bad function name provided to '$1': '$2'"
				fi
				fn="$2"
				shift 2

				declare "${flag}_fn=$fn"
				arity=$(get_arity "$fn")
				fn_args=()
				# Parse up to the arity number of arguments
				while [ $# -gt 0 ] && [ ${#fn_args[@]} -lt "$arity" ]; do
					fn_args+=("$1")
					shift
				done

				# Fail if there's an arity mismatch
				if [ ${#fn_args[@]} -lt "$arity" ]; then
					err_die "Bad number of arguments provided to '$1': expected $arity, got ${#fn_args[@]}"
				fi

				# Create an alias and then assign without using eval
				declare -n "target_args=${flag}_args"
				# shellcheck disable=SC2034
				target_args=("${fn_args[@]}")
				continue
				;;

			*) err_die "Bad check flag: '$1'" ;;
		esac
		shift
	done

	# Check order matters
	# - if skip function is set and check passes
	# - if not always and there is a skip reason in the stack
	if [ -n "$skip_fn" ] && "$skip_fn" "${skip_args[@]}"; then
		output_skip "$rule" "$skip_reason"
		return "$RES_SKIP"

	elif [ "$always" = 0 ] && have_skip_reasons; then
		skip_reason="$(peek_skip_reason)"
		output_skip "$rule" "$skip_reason"
		return "$RES_SKIP"

	elif [ -n "$fail_fn" ] && "$fail_fn" "${fail_args[@]}"; then
		output_fail "$rule" "$fail_actual" "$fail_expected"
		[ -n "$fail_set_skip" ] && push_skip_reason "$fail_set_skip"
		return "$RES_FAIL"

	elif [ -n "$warn_fn" ] && "$warn_fn" "${warn_args[@]}"; then
		output_warn "$rule" "$warn_actual" "$warn_expected"
		return "$RES_WARN"

	else
		output_pass "$rule" "$pass_reason"
	fi
}

check_name() {
	local type="$1"
	local name="$2"

	check \
		-rule "$type name must be either a real name 'firstname lastname' or a nickname/alias/handle" \
		-fail-if is_not_alias "$name" \
		-warn-if is_not_name "$name" \
		-warn-actual "$name seems to be a nickname or an alias" \
		-warn-expected "a real name 'firstname lastname'"
}

check_email() {
	local type="$1"
	local email="$2"

	check \
		-rule "$type email must not be a GitHub noreply email" \
		-fail-if is_github_noreply "$email" \
		-fail-expected 'a real email address'
}

check_subject() {
	local subject="$1"

	is_revert "$subject" && push_skip_reason 'revert commit'

	check \
		-rule 'Commit subject must not start with whitespace' \
		-fail-if starts_with_space "$subject"

	local reason='missing prefix'
	# shellcheck disable=SC2016
	check \
		-rule 'Commit subject must start with `<package name or prefix>: `' \
		-fail-if has_no_prefix "$subject" \
		-fail-set-skip "$reason"

	check \
		-rule 'Commit subject must start with a lower-case word after the prefix' \
		-fail-if is_first_word_caps "$subject"

	pop_if_skip_reason "$reason"

	check \
		-rule 'Commit subject must not end with a period' \
		-fail-if ends_with_period "$subject"

	# Check subject length first for hard limit which results in an error and
	# otherwise for a soft limit which results in a warning.
	check \
		-rule "Commit subject must be <= $MAX_SUBJECT_LEN_HARD (and should be <= $MAX_SUBJECT_LEN_SOFT) characters long" \
		-fail-if is_gt "${#subject}" "$MAX_SUBJECT_LEN_HARD" \
		-fail-actual "subject is ${#subject} characters long" \
		-warn-if is_gt "${#subject}" "$MAX_SUBJECT_LEN_SOFT" \
		-warn-actual "subject is ${#subject} characters long"

	local res=$?
	if is_warn "$res" || is_fail "$res"; then
		output_split_fail_ex "$MAX_SUBJECT_LEN_SOFT" "$MAX_SUBJECT_LEN_HARD" "$subject"
	fi
}

check_body() {
	local body="$1"
	local sob="$2"

	local reason="missing or doesn't match author"
	# shellcheck disable=SC2016
	check \
		-rule '`Signed-off-by` must match author' \
		-skip-if do_not_check_signoff \
		-skip-reason 'disabled by configuration' \
		-fail-if omits "$body" "$sob" \
		-fail-actual "$reason" \
		-fail-expected "\`$sob\`" \
		-fail-set-skip "$reason"

	# shellcheck disable=SC2016
	check \
		-rule '`Signed-off-by` must not be a GitHub noreply email' \
		-skip-if do_not_check_signoff \
		-skip-reason 'disabled by configuration' \
		-fail-if is_github_noreply "$body" \
		-fail-expected 'a real email address'

	pop_if_skip_reason "$reason"

	# Never skip this check based on other checks
	check \
		-rule 'Commit message must exist' \
		-always \
		-fail-if is_body_empty "$body" \
		-fail-set-skip 'missing commit message'

	local msg="Commit message lines should be <= $MAX_BODY_LINE_LEN characters long"
	if ! have_skip_reasons; then
		local body_line_too_long=0
		local line_num=0
		while IFS= read -r line; do
			line_num=$((line_num + 1))
			if [ ${#line} -gt "$MAX_BODY_LINE_LEN" ]; then
				if [ "$body_line_too_long" = 0 ]; then
					output_warn "$msg"
					body_line_too_long=1
				fi
				output_details "line $line_num is ${#line} characters long"
				output_split_fail "$MAX_BODY_LINE_LEN" "$line"
			fi
		done <<< "$body"
		[ "$body_line_too_long" = 0 ] && status_pass "$msg"
	else
		output_skip "$msg" "${SKIP_REASONS[-1]}"
	fi

	reset_skip_reasons
	has_base || push_skip_reason 'no base branch specified'

	check \
		-rule 'Commit to stable branch should be marked as cherry-picked' \
		-skip-if is_main_branch "$BASE_BRANCH" \
		-skip-reason "not a stable branch (\`${BASE_BRANCH#origin/}\`)" \
		-warn-if omits "$body" '(cherry picked from commit' \
		-warn-actual "a stable branch (\`${BASE_BRANCH#origin/}\`)"
}

main() {
	# Initialize GitHub actions output
	output 'content<<EOF'

	show_feedback && feedback
	check_exceptions
	show_legend && legend

	info "Checking PR #$PR_NUMBER"
	check \
		-rule 'Pull request must come from a feature branch' \
		-pass-reason "\`$HEAD_BRANCH\` branch" \
		-fail-if is_main_branch "$HEAD_BRANCH" \
		-fail-actual "\`$HEAD_BRANCH\` branch"
	echo

	# Combine rev-list and fetching commit data
	git "${REPO_PATH[@]}" rev-list --color=always --format="$GIT_FORMAT" ${BASE_BRANCH:+"$BASE_BRANCH"..}HEAD | {
		local commit_header
		local commit
		local author_name author_email
		local committer_name committer_email
		local subject body sob
		local parent_hashes

		# git rev-list automatically adds commit hash as the first line, skip it
		while IFS="$_F" read -r -d "$_R" \
			__skip__ \
			commit_header \
			commit \
			author_name \
			author_email \
			committer_name \
			committer_email \
			subject \
			body \
			sob \
			parent_hashes
		do
			HEADER_SET=0
			COMMIT="$commit"

			echo "$commit_header"

			check \
				-rule 'Pull request must not include merge commits' \
				-always \
				-fail-if is_merge "$parent_hashes"

			if [ $? = "$RES_FAIL" ]; then
				# No need to check anything else, since this is a merge commit
				echo
				continue
			fi

			reset_skip_reasons "$author_email"
			check_name 'Author' "$author_name"
			check_email 'Author' "$author_email"
			check_name 'Commit(ter)' "$committer_name"
			check_email 'Commit(ter)' "$committer_email"
			check_subject "$subject"
			reset_skip_reasons "$author_email"
			check_body "$body" "$sob"

			echo
		done
		exit "$FAIL"
	}
	FAIL=$?

	output 'EOF'

	exit "$FAIL"
}

main
