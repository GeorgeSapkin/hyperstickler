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

# Strip ANSI color codes from text and count occurrences of a pattern
count() {
	local text="$1"
	local pattern="$2"
	echo "$text" |
	sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' |
	grep -cF "$pattern" || true
}

status_wait() {
	printf '[\e[1;39m%s\e[0m] %s' 'wait' "$1"
}

run_test() {
	local description="$1"
	local expected_fails="$2"
	local expected_warns="$3"
	local expected_skips="$4"
	local author="$5"
	local email="$6"
	local subject="$7"
	local body="$8"
	local merge="${9:-0}"
	local injection_file="${10:-}"

	local actual_fails actual_warns actual_skips

	TEST_COUNT=$((TEST_COUNT + 1))
	status_wait "$description"

	[ "$merge" = 1 ] && git switch "$BASE_BRANCH" >/dev/null 2>&1
	commit "$author" "$email" "$subject" "$body" >/dev/null
	[ "$merge" = 1 ] \
		&& git switch "$HEAD_BRANCH" >/dev/null 2>&1 \
		&& git merge --no-ff "$BASE_BRANCH" -m "Merge branch '$BASE_BRANCH' into '$HEAD_BRANCH" >/dev/null 2>&1

	set +e
	output=$("$CHECKER_SCRIPT" "$REPO_DIR" 2>&1)
	set -e

	actual_fails=$(count "$output" '[fail]')
	actual_warns=$(count "$output" '[warn]')
	actual_skips=$(count "$output" '[skip]')

	# Move cursor to the beginning of the line and clear it
	printf '\r\e[K'

	if [ -n "$injection_file" ] && [ -f "$injection_file" ]; then
		status_fail "$description"
		echo "       Injection test failed: file '$injection_file' was created."
		rm -f "$injection_file"
	elif [ "$actual_fails" = "$expected_fails" ] && [ "$actual_warns" = "$expected_warns" ] && [ "$actual_skips" = "$expected_skips" ]; then
		status_pass "$description"
		PASS_COUNT=$((PASS_COUNT + 1))
	else
		status_fail "$description"
		if [ "$actual_fails" -ne "$expected_fails" ]; then
			echo "       Expected $expected_fails failure(s), but got $actual_fails."
		fi
		if [ "$actual_warns" -ne "$expected_warns" ]; then
			echo "       Expected $expected_warns warning(s), but got $actual_warns."
		fi
		if [ "$actual_skips" -ne "$expected_skips" ]; then
			echo "       Expected $expected_skips skip(s), but got $actual_skips."
		fi
		echo
		echo '       Output:'
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

echo
echo 'Starting test suite'
echo

# Good commits

run_test 'Good commit' 0 0 1 \
'Good Author' 'good.author@example.com' \
'package: add new feature' \
'This commit follows all the rules.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Subject: double prefix' 0 0 1 \
'Good Author' 'good.author@example.com' \
'kernel: 6.18: add new feature' \
'This commit follows all the rules.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Good commit with a list' 0 0 1 \
'Good Author' 'good.author@example.com' \
'package: add new feature' \
'- item 0
- item 1
- item 2
- item 3
- item 4

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Revert commit' 0 0 5 \
'Revert Author' 'revert.author@example.com' \
"Revert 'package: add new feature'" \
'This reverts commit.

Signed-off-by: Revert Author <revert.author@example.com>'

# shellcheck disable=SC2016
run_test 'Body: malicious body shell injection' 0 0 1 \
'Good Author' 'good.author@example.com' \
'test: malicious body shell injection' \
'$(touch /tmp/pwned-by-body)
Signed-off-by: Good Author <good.author@example.com>' \
0 '/tmp/pwned-by-body'

run_test 'Body: malicious body check injection' 0 0 1 \
'Good Author' 'good.author@example.com' \
'test: malicious body check injection' \
'-skip-if is_gt 1 0 && touch /tmp/pwned-by-check
Signed-off-by: Good Author <good.author@example.com>' \
0 '/tmp/pwned-by-check'

export CHECK_SIGNOFF='false'
run_test 'Body: missing Signed-off-by but check disabled' 0 0 3 \
'Good Author' 'good.author@example.com' \
'test: fail on missing signed-off-by' \
'The Signed-off-by line is missing.'

run_test 'Body: mismatched Signed-off-by but check disabled' 0 0 3 \
'Good Author' 'good.author@example.com' \
'test: fail on mismatched signed-off-by' \
'The Signed-off-by line is for someone else.

Signed-off-by: Mismatched Person <mismatched@example.com>'
export CHECK_SIGNOFF='true'

# Commits with failures

run_test 'Bad author email (GitHub noreply)' 3 0 1 \
'Bad Email' 'bad.email@users.noreply.github.com' \
'test: fail on bad author email' \
'Author email is a GitHub noreply address.

Signed-off-by: Bad Email <bad.email@users.noreply.github.com>'

run_test 'Subject: no prefix' 1 0 2 \
'Good Author' 'good.author@example.com' \
'This subject has no prefix' \
'This commit should fail.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Subject: capitalized first word' 1 0 1 \
'Good Author' 'good.author@example.com' \
'package: Capitalized first word' \
'This commit should fail.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Subject: ends with a period' 1 0 1 \
'Good Author' 'good.author@example.com' \
'package: subject ends with a period.' \
'This commit should fail.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Subject: too long (hard limit)' 1 0 1 \
'Good Author' 'good.author@example.com' \
'package: this subject is way too long and should fail the hard limit check of 60 chars' \
'This commit should fail.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Body: missing Signed-off-by' 1 0 2 \
'Good Author' 'good.author@example.com' \
'test: fail on missing signed-off-by' \
'The Signed-off-by line is missing.'

run_test 'Body: mismatched Signed-off-by' 1 0 2 \
'Good Author' 'good.author@example.com' \
'test: fail on mismatched signed-off-by' \
'The Signed-off-by line is for someone else.

Signed-off-by: Mismatched Person <mismatched@example.com>'

run_test 'Body: empty' 1 0 2 \
'Good Author' 'good.author@example.com' \
'test: fail on empty body' \
'Signed-off-by: Good Author <good.author@example.com>'

# Commits with warnings

run_test 'Author name is a single word' 0 2 1 \
'Nickname' 'nickname@example.com' \
'test: warn on single-word author name' \
'Author name is a single word.

Signed-off-by: Nickname <nickname@example.com>'

run_test 'Subject: too long (soft limit)' 0 1 1 \
'Good Author' 'good.author@example.com' \
'package: this subject is long and should trigger a warning' \
'This commit should warn on subject length.

Signed-off-by: Good Author <good.author@example.com>'

run_test 'Body: line too long' 0 1 1 \
'Good Author' 'good.author@example.com' \
'test: warn on long body line' \
'This line in the commit body is extremely long and should definitely exceed the seventy-five character limit imposed by the check script.

Signed-off-by: Good Author <good.author@example.com>'

# Exception tests

export EXCLUDE_DEPENDABOT='true'
run_test 'Exception: dependabot' 0 0 12 \
'dependabot[bot]' 'dependabot[bot]@users.noreply.github.com' \
'CI: bump something from 1 to 2' \
'This commit should skip most tests.'
export EXCLUDE_DEPENDABOT='false'

run_test 'No exception: dependabot' 3 2 2 \
'dependabot[bot]' 'dependabot[bot]@users.noreply.github.com' \
'CI: bump something from 1 to 2' \
'This commit should fail most tests.'

export EXCLUDE_WEBLATE='true'
run_test 'Exception: weblate' 0 0 12 \
'Hosted Weblate' 'hosted@weblate.org' \
'Translated using Weblate (English)' \
'This commit should skip most tests.'
export EXCLUDE_WEBLATE='false'

run_test 'No exception: weblate' 2 0 3 \
'Hosted Weblate' 'hosted@weblate.org' \
'Translated using Weblate (English)' \
'This commit should fail most tests.'

# Merge commit test

run_test 'Merge commit' 1 0 0 \
'Merge Author' 'merge.author@example.com' \
'feat: add something to be merged' \
'This commit will be part of a merge.' \
1

# PR from master test

export HEAD_BRANCH='master'
run_test 'PR from master' 1 0 1 \
'Good Author' 'good.author@example.com' \
'package: add new feature' \
"This commit follows all the rules but PR doesn't.

Signed-off-by: Good Author <good.author@example.com>"

echo
echo 'Test suite finished'
echo "Summary: $PASS_COUNT/$TEST_COUNT tests passed"

[ "$PASS_COUNT" != "$TEST_COUNT" ] \
	&& exit 1 \
	|| exit 0
