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

if [ "$MAX_SUBJECT_LEN_SOFT" -gt "$MAX_SUBJECT_LEN_HARD" ]; then
	echo "MAX_SUBJECT_LEN_SOFT cannot be larger than MAX_SUBJECT_LEN_HARD, now $MAX_SUBJECT_LEN_SOFT and $MAX_SUBJECT_LEN_HARD" >&2
	exit 1
fi

INDENT_MD='    '
INDENT_TERM='       '

DEPENDABOT_EMAIL='dependabot[bot]@users.noreply.github.com'
GITHUB_NOREPLY_EMAIL='@users.noreply.github.com'
WEBLATE_EMAIL='hosted@weblate.org'

FEEDBACK_URL=${FEEDBACK_URL:-'https://github.com/georgesapkin/hyperstickler/issues'}

EMOJI_WARN=':large_orange_diamond:'
EMOJI_FAIL=':x:'

PREFIX_REGEX='^([0-9A-Za-z,+/._-]+: )+'

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

ACTION_PATH=${ACTION_PATH:+"$ACTION_PATH/src"}
ACTION_PATH=${ACTION_PATH:-$(dirname "$(readlink -f "$0")")}
source "$ACTION_PATH/helpers.sh"

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
ends_with_period()     { grep -qEe "\.$" <<< "$1"; }
exclude_dependabot()   { [ "$EXCLUDE_DEPENDABOT" = 'true' ]; }
exclude_weblate()      { [ "$EXCLUDE_WEBLATE" = 'true' ]; }
git_format()           { git "${REPO_PATH[@]}" show -s --format="$1" "$COMMIT"; }
# shellcheck disable=SC2329
has_no_prefix()        { ! grep -qEe "$PREFIX_REGEX" <<< "$1"; }
# shellcheck disable=SC2329
is_first_word_caps()   { grep -qEe "${PREFIX_REGEX}[A-Z]" <<< "$1"; }
# shellcheck disable=SC2329
is_body_empty()        { ! echo "$1" | grep -v 'Signed-off-by:' | grep -q '[^[:space:]]'; }
# shellcheck disable=SC2329
is_github_noreply()    { grep -iqF "$GITHUB_NOREPLY_EMAIL" <<< "$1"; }
# shellcheck disable=SC2329
is_gt()                { [ "$1" -gt "$2" ]; }
# shellcheck disable=SC2329
is_main_branch()       { [[ "$1" =~ ^(origin/)?(main|master)$ ]]; }
# shellcheck disable=SC2329
is_merge()             { git_format '%P' | grep -qF ' '; }
# shellcheck disable=SC2329
is_not_alias()         { ! grep -qEe '\S' <<< "$1"; }
# shellcheck disable=SC2329
is_not_name()          { ! grep -qEe '\S+\s\S+' <<< "$1"; }
is_revert()            { grep -qEe '^Revert ' <<< "$1"; }
# shellcheck disable=SC2329
omits()                { ! grep -qF "$2" <<< "$1"; }
show_legend()          { [ "$SHOW_LEGEND" = 'true' ]; }

have_exceptions() { [ "${#EXCEPTION_NAMES[@]}" -gt 0 ]; }

push_exception() {
	EXCEPTION_NAMES[${#EXCEPTION_NAMES[@]}]="$1";
	EXCEPTION_EMAILS[${#EXCEPTION_EMAILS[@]}]="$2";
}

is_exception() {
	local email="$1"
	if [ -z "$email" ]; then
		return 1
	fi

	for idx in "${!EXCEPTION_EMAILS[@]}"; do
		if grep -iqF "${EXCEPTION_EMAILS[$idx]}" <<< "$email"; then
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
}

have_reasons()    { [ "${#SKIP_REASONS[@]}" -gt 0 ]; }
is_reason()       { have_reasons && [ "${SKIP_REASONS[-1]}" = "$1" ]; }
peak_reason()     { have_reasons && echo "${SKIP_REASONS[-1]}"; }
pop_reason()      { unset "SKIP_REASONS[-1]"; }
pop_if_reason()   { is_reason "$1" && pop_reason; }
push_reason()     { SKIP_REASONS[${#SKIP_REASONS[@]}]="$1"; }

reset_reasons() {
	local author_email="$1"
	local exception

	SKIP_REASONS=()
	exception="$(is_exception "$author_email")"
	# shellcheck disable=SC2181
	if [ $? = 0 ]; then
		push_reason "authored by $exception"
	fi
}

get_arity() {
	local fn_name="$1"
	local fn_body
	fn_body=$(declare -f "$fn_name")

	# Count the highest number used in a positional parameter like $1, $2, etc.
	local arity
	arity=$(echo "$fn_body" | grep -o '\$[0-9]\+' | sed 's/\$//' | sort -rn | head -n1)

	if [ -z "$arity" ]; then
		echo 0
	else
		echo "$arity"
	fi
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
				declare "${flag}_fn=$2"
				if ! declare -F "$2" >/dev/null; then
					err_die "Bad function name provided to '$1': '$2'"
				fi
				shift 2

				# Get the actual function name from the declare above and check
				# its arity
				fn=$(declare -p "${flag}_fn" | sed -e "s/.*\"\(.*\)\"/\1/")
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

			*)
				err_die "Bad check flag: '$1'"
				;;
		esac
		shift
	done

	# Check order matters
	# - if skip function is set and check passes
	# - if not always and there is a skip reason in the stack
	if [ -n "$skip_fn" ] && "$skip_fn" "${skip_args[@]}"; then
		output_skip "$rule" "$skip_reason"
		return "$RES_SKIP"

	elif [ "$always" = 0 ] && have_reasons; then
		skip_reason="$(peak_reason)"
		output_skip "$rule" "$skip_reason"
		return "$RES_SKIP"

	elif [ -n "$fail_fn" ] && "$fail_fn" "${fail_args[@]}"; then
		output_fail "$rule" "$fail_actual" "$fail_expected"
		[ -n "$fail_set_skip" ] && push_reason "$fail_set_skip"
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

	is_revert "$subject" && push_reason 'revert commit'

	local reason='missing prefix'
	# shellcheck disable=SC2016
	check \
		-rule 'Commit subject must start with `<package name or prefix>: `' \
		-fail-if has_no_prefix "$subject" \
		-fail-set-skip "$reason"

	check \
		-rule 'Commit subject must start with a lower-case word after the prefix' \
		-fail-if is_first_word_caps "$subject"

	pop_if_reason "$reason"

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
	if [ "$res" = "$RES_WARN" ] || [ "$res" = "$RES_FAIL" ]; then
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

	pop_if_reason "$reason"

	# Never skip this check based on other checks
	check \
		-rule 'Commit message must exist' \
		-always \
		-fail-if is_body_empty "$body" \
		-fail-set-skip 'missing commit message'

	local msg="Commit message lines should be <= $MAX_BODY_LINE_LEN characters long"
	if ! have_reasons; then
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
		if [ "$body_line_too_long" = 0 ]; then
			status_pass "$msg"
		fi
	else
		output_skip "$msg" "${SKIP_REASONS[-1]}"
	fi

	# Never skip this check based on other checks
	check \
		-rule 'Commit to stable branch should be marked as cherry-picked' \
		-always \
		-skip-if is_main_branch "$BASE_BRANCH" \
		-skip-reason "not a stable branch (\`${BASE_BRANCH#origin/}\`)" \
		-warn-if omits "$body" '(cherry picked from commit' \
		-warn-actual "a stable branch (\`${BASE_BRANCH#origin/}\`)"
}

main() {
	local author_email
	local author_name
	local body
	local commit
	local committer_email
	local committer_name
	local subject

	# Initialize GitHub actions output
	output 'content<<EOF'

	cat <<-EOF
	Something broken? Consider providing feedback:
	${FEEDBACK_URL}

	EOF

	check_exceptions
	echo

	show_legend && legend

	info "Checking PR #$PR_NUMBER"
	check \
		-rule 'Pull request must come from a feature branch' \
		-pass-reason "\`$HEAD_BRANCH\` branch" \
		-fail-if is_main_branch "$HEAD_BRANCH" \
		-fail-actual "\`$HEAD_BRANCH\` branch"
	echo

	for commit in $(git "${REPO_PATH[@]}" rev-list "$BASE_BRANCH"..HEAD); do
		HEADER_SET=0
		COMMIT="$commit"

		git "${REPO_PATH[@]}" log -1 --color --pretty=full "$commit"
		echo

		check \
			-rule 'Pull request must not include merge commits' \
			-always \
			-fail-if is_merge

		if [ $? = "$RES_FAIL" ]; then
			# No need to check anything else, since this is a merge commit
			echo
			continue
		fi

		author_name="$(git_format '%aN')"
		author_email="$(git_format '%aE')"
		committer_name="$(git_format '%cN')"
		committer_email="$(git_format '%cE')"

		reset_reasons "$author_email"

		check_name 'Author' "$author_name"
		check_email 'Author' "$author_email"
		check_name 'Commit(ter)' "$committer_name"
		check_email 'Commit(ter)' "$committer_email"

		subject="$(git_format '%s')"
		check_subject "$subject"

		reset_reasons "$author_email"

		body="$(git_format '%b')"
		sob="$(git_format 'Signed-off-by: %aN <%aE>' "$commit")"
		check_body "$body" "$sob"

		echo
	done

	output 'EOF'

	exit "$FAIL"
}

main
