#!/bin/bash
#
# Copyright (C) 2025, George Sapkin
#
# SPDX-License-Identifier: GPL-2.0-only

set -e

export BASE_BRANCH='main'
export HEAD_BRANCH='feature-branch'
export PR_NUMBER='123'
export SHOW_LEGEND='false'
export CHECK_SIGNOFF='true'

REPO_DIR="${1:-}"

CHECKER_SCRIPT="$(dirname "$(readlink -f "$0")")/check_formalities.sh"

source "$(dirname "$(readlink -f "$0")")/helpers.sh"

TEST_COUNT=0
PASS_COUNT=0

EXP_GOOD="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3"
EXP_DOUBLE_PREFIX="$EXP_GOOD"
EXP_BAD_CHECK_PARSE="$EXP_GOOD"
EXP_REVERT="0 0 0 0 0 0 3 3 3 3 3 0 0 0 0 3"
EXP_MALICIOUS_SHELL="$EXP_GOOD"
EXP_MALICIOUS_CHECK="$EXP_GOOD"
EXP_NO_SOB_CHECK="0 0 0 0 0 0 0 0 0 0 0 3 3 0 0 3"
EXP_BAD_SOB_CHECK="$EXP_NO_SOB_CHECK"
EXP_BAD_EMAIL="0 0 0 1 0 1 0 0 0 0 0 0 1 0 0 3"
EXP_SUBJ_SPACE="0 0 0 0 0 0 1 1 3 0 0 0 0 0 0 3"
EXP_SUBJ_NO_PREFIX="0 0 0 0 0 0 0 1 3 0 0 0 0 0 0 3"
EXP_SUBJ_CAPS="0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 3"
EXP_SUBJ_PERIOD="0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 3"
EXP_SUBJ_LONG_HARD="0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 3"
EXP_SOB_MISS="0 0 0 0 0 0 0 0 0 0 0 1 3 0 0 3"
EXP_SOB_BAD="$EXP_SOB_MISS"
EXP_EMPTY_BODY="0 0 0 0 0 0 0 0 0 0 0 0 0 1 3 3"
EXP_NAME_WARN="0 0 2 0 2 0 0 0 0 0 0 0 0 0 0 3"
EXP_SUBJ_LONG_SOFT="0 0 0 0 0 0 0 0 0 0 2 0 0 0 0 3"
EXP_BODY_LONG="0 0 0 0 0 0 0 0 0 0 0 0 0 0 2 3"
EXP_DEPENDABOT_EXCEPT="0 0 3 3 3 3 3 3 3 3 3 3 3 0 3 3"
EXP_DEPENDABOT_FAIL="0 0 2 1 2 1 0 0 0 0 0 1 3 0 0 3"
EXP_WEBLATE_EXCEPT="$EXP_DEPENDABOT_EXCEPT"
EXP_WEBLATE_FAIL="0 0 0 0 0 0 0 1 3 0 0 1 3 0 0 3"
EXP_MERGE="0 1"
EXP_PR_MASTER="1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3"

cleanup() {
	if [ -d "$REPO_DIR" ]; then
		echo "Cleaning up Git repository in $REPO_DIR"
		rm -rf "$REPO_DIR"
	fi
}

trap cleanup EXIT

commit() {
	local author="$1"
	local email="$2"
	local subject="$3"
	local body="$4"

	touch "file-$(date +%s-%N).txt"
	git add .

	GIT_COMMITTER_NAME="$author" GIT_COMMITTER_EMAIL="$email" \
		git commit --author="$author <${email}>" -m "$subject" -m "$body"
}

status_wait() {
	printf '[\e[1;39m%s\e[0m] %s' 'wait' "$1"
}

to_code() {
	case "$1" in
		pass) echo '0' ;;
		fail) echo '1' ;;
		warn) echo '2' ;;
		skip) echo '3' ;;
		*)    err_die "Bad status: '$1'" ;;
	esac
}

to_status() {
	case "$1" in
		0) echo 'pass' ;;
		1) echo 'fail' ;;
		2) echo 'warn' ;;
		3) echo 'skip' ;;
		*) err_die "Bad status code: '$1'" ;;
	esac
}

run_test() {
	local description="$1"
	local expected_results_str="$2"
	local author="$3"
	local email="$4"
	local subject="$5"
	local body="$6"
	local merge="${7:-0}"
	local injection_file="${8:-}"

	status_wait "$description"

	local expected_results
	read -r -a expected_results <<< "$expected_results_str"

	local output
	local line
	local check_idx=0
	local fail=0
	local output=""
	local injection_failed=0

	TEST_COUNT=$((TEST_COUNT + 1))

	[ "$merge" = 1 ] && git switch "$BASE_BRANCH" >/dev/null 2>&1
	commit "$author" "$email" "$subject" "$body" >/dev/null
	[ "$merge" = 1 ] \
		&& git switch "$HEAD_BRANCH" >/dev/null 2>&1 \
		&& git merge --no-ff "$BASE_BRANCH" -m "Merge branch '$BASE_BRANCH' into '$HEAD_BRANCH" >/dev/null 2>&1

	set +e
	output=$("$CHECKER_SCRIPT" "$REPO_DIR" 2>&1)
	local exit_code=$?
	set -e

	# Move cursor to the beginning of the line and clear it
	printf '\r\e[K'

	if [ -n "$injection_file" ] && [ -f "$injection_file" ]; then
		fail=1
		injection_failed=1
		status_fail "$description"
		echo "       Injection test failed: file '$injection_file' was created."
		rm -f "$injection_file"
	fi

	local raw_output="$output"
	output=""

	local expect_failure=0
	for res in "${expected_results[@]}"; do
		if [ "$res" = 1 ]; then
			expect_failure=1
			break
		fi
	done

	if [ "$expect_failure" = 1 ]; then
		if [ "$exit_code" = 0 ]; then
			fail=1
			output+=$'\e[1;31mExpected test failure, but got exit code 0\e[0m\n\n'
		fi
	elif [ "$exit_code" != 0 ]; then
		fail=1
		output+=$'\e[1;31mExpected test success, but got exit code '"$exit_code"$'\e[0m\n\n'
	fi

	while IFS= read -r line; do
		local clean_line
		# Strip ANSI color codes
		clean_line=$(echo "$line" | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g')

		if [[ "$clean_line" =~ ^\[(pass|fail|warn|skip)\] ]]; then
			local actual_status="${BASH_REMATCH[1]}"

			if [ "$check_idx" -ge "${#expected_results[@]}" ]; then
				fail=1
				output+="$line"$'\n'
				output+=$'       \e[1;31mUnexpected result: '"$actual_status"$'\e[0m\n'

			else
				local expected_code="${expected_results[$check_idx]}"
				local actual_code
				actual_code=$(to_code "$actual_status")

				if [ "$actual_code" != "$expected_code" ]; then
					fail=1
					local expected_status
					expected_status=$(to_status "$expected_code")
					output+="$line"$'\n'
					output+=$'       \e[1;31mExpected: '"$expected_status"$'\e[0m\n'
				else
					output+="$line"$'\n'
				fi
			fi
			check_idx=$((check_idx + 1))
		else
			output+="$line"$'\n'
		fi
	done <<< "$raw_output"

	if [ "$check_idx" -lt "${#expected_results[@]}" ]; then
		fail=1
		output+=$'       \e[1;31mMissing expected results starting from index '"$check_idx"$'\e[0m\n'
	fi

	if [ "$fail" -eq 0 ]; then
		status_pass "$description"
		PASS_COUNT=$((PASS_COUNT + 1))
	else
		[ "$injection_failed" = 0 ] && status_fail "$description"
		output+=$'\n       Output:'
		# shellcheck disable=SC2001
		sed 's/^/       /' <<< "$output"
	fi

	git reset --hard HEAD~1 >/dev/null
}

if [ -z "$REPO_DIR" ]; then
	REPO_DIR=$(mktemp -d)
else
	if [ -d "$REPO_DIR" ]; then
		echo "Test repository '$REPO_DIR' already exists" >&2
		exit 1
	fi
	mkdir "$REPO_DIR"
fi

cd "$REPO_DIR"

git init -b "$BASE_BRANCH"
git config user.name 'Test User'
git config user.email 'test.user@example.com'

commit 'Initial Committer' 'initial@example.com' \
'initial: commit' \
'This is the first main commit.' >/dev/null

git switch -C "$HEAD_BRANCH"

echo $'\nStarting test suite\n'

# Good commits

run_test 'Good commit' "$EXP_GOOD" \
'Good Author' 'good.author@example.com' \
'package: add new feature' \
'This commit follows all the rules.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Subject: double prefix' "$EXP_DOUBLE_PREFIX" \
'Good Author' 'good.author@example.com' \
'kernel: 6.18: add new feature' \
'This commit follows all the rules.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Bad check parsing test' "$EXP_BAD_CHECK_PARSE" \
'Good Author' 'good.author@example.com' \
'package: add new feature' \
'- item 0
- item 1
- item 2
- item 3
- item 4

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Revert commit' "$EXP_REVERT" \
'Revert Author' 'revert.author@example.com' \
"Revert 'package: add new feature'" \
'This reverts commit.

Signed-off-by: Revert Author <revert.author@example.com>'

# shellcheck disable=SC2016
run_test 'Body: malicious body shell injection' "$EXP_MALICIOUS_SHELL" \
'Good Author' 'good.author@example.com' \
'test: malicious body shell injection' \
'$(touch /tmp/pwned-by-body)
Signed-off-by: Good Author <good.author@example.com>' \
0 '/tmp/pwned-by-body'

run_test 'Body: malicious body check injection' "$EXP_MALICIOUS_CHECK" \
'Good Author' 'good.author@example.com' \
'test: malicious body check injection' \
'-skip-if is_gt 1 0 && touch /tmp/pwned-by-check
Signed-off-by: Good Author <good.author@example.com>' \
0 '/tmp/pwned-by-check'

export CHECK_SIGNOFF='false'
run_test 'Body: missing Signed-off-by but check disabled' "$EXP_NO_SOB_CHECK" \
'Good Author' 'good.author@example.com' \
'test: fail on missing signed-off-by' \
'The Signed-off-by line is missing.'

run_test 'Body: mismatched Signed-off-by but check disabled' "$EXP_BAD_SOB_CHECK" \
'Good Author' 'good.author@example.com' \
'test: fail on mismatched signed-off-by' \
'The Signed-off-by line is for someone else.

Signed-off-by: Mismatched Person <mismatched@example.com>'
export CHECK_SIGNOFF='true'

# Commits with failures

run_test 'Bad author email (GitHub noreply)' "$EXP_BAD_EMAIL" \
'Bad Email' 'bad.email@users.noreply.github.com' \
'test: fail on bad author email' \
'Author email is a GitHub noreply address.

Signed-off-by: Bad Email <bad.email@users.noreply.github.com>'

run_test 'Subject: starts with whitespace' "$EXP_SUBJ_SPACE" \
'Good Author' 'good.author@example.com' \
' package: subject starts with whitespace' \
'This commit should fail.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Subject: no prefix' "$EXP_SUBJ_NO_PREFIX" \
'Good Author' 'good.author@example.com' \
'This subject has no prefix' \
'This commit should fail.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Subject: capitalized first word' "$EXP_SUBJ_CAPS" \
'Good Author' 'good.author@example.com' \
'package: Capitalized first word' \
'This commit should fail.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Subject: ends with a period' "$EXP_SUBJ_PERIOD" \
'Good Author' 'good.author@example.com' \
'package: subject ends with a period.' \
'This commit should fail.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Subject: too long (hard limit)' "$EXP_SUBJ_LONG_HARD" \
'Good Author' 'good.author@example.com' \
'package: this subject is way too long and should fail the hard limit check of 60 chars' \
'This commit should fail.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Body: missing Signed-off-by' "$EXP_SOB_MISS" \
'Good Author' 'good.author@example.com' \
'test: fail on missing signed-off-by' \
'The Signed-off-by line is missing.'

run_test 'Body: mismatched Signed-off-by' "$EXP_SOB_BAD" \
'Good Author' 'good.author@example.com' \
'test: fail on mismatched signed-off-by' \
'The Signed-off-by line is for someone else.

Signed-off-by: Mismatched Person <mismatched@example.com>'

run_test 'Body: empty' "$EXP_EMPTY_BODY" \
'Good Author' 'good.author@example.com' \
'test: fail on empty body' \
'Signed-off-by: Good Author <good.author@example.com>'

# Commits with warnings

run_test 'Author name is a single word' "$EXP_NAME_WARN" \
'Nickname' 'nickname@example.com' \
'test: warn on single-word author name' \
'Author name is a single word.

Signed-off-by: Nickname <nickname@example.com>'

run_test 'Subject: too long (soft limit)' "$EXP_SUBJ_LONG_SOFT" \
'Good Author' 'good.author@example.com' \
'package: this subject is long and should trigger a warning' \
'This commit should warn on subject length.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Body: line too long' "$EXP_BODY_LONG" \
'Good Author' 'good.author@example.com' \
'test: warn on long body line' \
'This line in the commit body is extremely long and should definitely exceed the seventy-five character limit imposed by the check script.

Signed-off-by: Good Author <good.author@example.com>'

# Exception tests

export EXCLUDE_DEPENDABOT='true'
run_test 'Exception: dependabot' "$EXP_DEPENDABOT_EXCEPT" \
'dependabot[bot]' 'dependabot[bot]@users.noreply.github.com' \
'CI: bump something from 1 to 2' \
'This commit should skip most tests.'
export EXCLUDE_DEPENDABOT='false'

run_test 'No exception: dependabot' "$EXP_DEPENDABOT_FAIL" \
'dependabot[bot]' 'dependabot[bot]@users.noreply.github.com' \
'CI: bump something from 1 to 2' \
'This commit should fail most tests.'

export EXCLUDE_WEBLATE='true'
run_test 'Exception: weblate' "$EXP_WEBLATE_EXCEPT" \
'Hosted Weblate' 'hosted@weblate.org' \
'Translated using Weblate (English)' \
'This commit should skip most tests.'
export EXCLUDE_WEBLATE='false'

run_test 'No exception: weblate' "$EXP_WEBLATE_FAIL" \
'Hosted Weblate' 'hosted@weblate.org' \
'Translated using Weblate (English)' \
'This commit should fail most tests.'

# Merge commit test

run_test 'Merge commit' "$EXP_MERGE" \
'Merge Author' 'merge.author@example.com' \
'feat: add something to be merged' \
'This commit will be part of a merge.' \
1

# PR from master test

export HEAD_BRANCH='master'
run_test 'PR from master' "$EXP_PR_MASTER" \
'Good Author' 'good.author@example.com' \
'package: add new feature' \
"This commit follows all the rules but PR doesn't.

Signed-off-by: Good Author <good.author@example.com>"

echo $'\nTest suite finished'
echo "Summary: $PASS_COUNT/$TEST_COUNT tests passed"

[ "$PASS_COUNT" != "$TEST_COUNT" ] \
	&& exit 1 \
	|| exit 0
