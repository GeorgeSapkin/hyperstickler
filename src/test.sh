#!/usr/bin/env bash
#
# Copyright (C) 2025, George Sapkin
#
# SPDX-License-Identifier: GPL-2.0-only

# Default exports
export BASE_BRANCH='main'
export CHECK_BRANCH='true'
export CHECK_SIGNOFF='true'
export HEAD_BRANCH='feature-branch'
export PR_NUMBER='123'
export SHOW_LEGEND='false'

MAX_JOBS=$(nproc --all 2>/dev/null || echo 8)
MAX_TEST_WAIT=50

VERBOSE=
REPO_DIR=

CHECKER_SCRIPT="$(dirname "$(readlink -f "$0")")/check_formalities.sh"

source "$(dirname "$(readlink -f "$0")")/helpers.sh"

AUTHORS=()
BODIES=()
DESCRIPTIONS=()
EMAILS=()
EXPECTED_RESULTS=()
INJECTIONS=()
MERGES=()
SUBJECTS=()

ENV_CHECK_BRANCH=()
ENV_CHECK_SIGNOFF=()
ENV_EXCLUDE_DEPENDABOT=()
ENV_EXCLUDE_WEBLATE=()
ENV_HEAD_BRANCH=()

define() {
	local name expected author email subject body merge exists
	local check_branch check_signoff exclude_dependabot exclude_weblate head_branch

	while [ $# -gt 0 ]; do
		case "$1" in
			-author)   author="$2";    shift ;;
			-email)    email="$2";     shift ;;
			-expected) expected="$2";  shift ;;
			-exists)   exists="$2";    shift ;;
			-merge)    merge="$2";     shift ;;
			-subject)  subject="$2";   shift ;;
			-test)     name="$2";      shift ;;

			-body)
				if [ -n "$2" ] && [[ "$2" != -* ]]; then
					body="$2"
					shift
				else
					body="$(cat)"
				fi
				;;

			-check-branch)  check_branch="$2";       shift ;;
			-check-signoff) check_signoff="$2";      shift ;;
			-no-dependabot) exclude_dependabot="$2"; shift ;;
			-no-weblate)    exclude_weblate="$2";    shift ;;
			-head-branch)   head_branch="$2";        shift ;;
			*)
				err_die "Unknown argument to define: $1"
				;;
		esac
		shift
	done

	AUTHORS+=("$author")
	BODIES+=("$body")
	DESCRIPTIONS+=("$name")
	EMAILS+=("$email")
	EXPECTED_RESULTS+=("$expected")
	INJECTIONS+=("${exists:-}")
	MERGES+=("${merge:-0}")
	SUBJECTS+=("$subject")

	ENV_CHECK_BRANCH+=("${check_branch:-${CHECK_BRANCH:-}}")
	ENV_CHECK_SIGNOFF+=("${check_signoff:-${CHECK_SIGNOFF:-}}")
	ENV_EXCLUDE_DEPENDABOT+=("${exclude_dependabot:-${EXCLUDE_DEPENDABOT:-}}")
	ENV_EXCLUDE_WEBLATE+=("${exclude_weblate:-${EXCLUDE_WEBLATE:-}}")
	ENV_HEAD_BRANCH+=("${head_branch:-${HEAD_BRANCH:-}}")
}

define \
	-test          'Good commit' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'package: add new feature' \
	-body          <<-'EOF'
		This commit follows all the rules.

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Subject: double prefix' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'kernel: 6.18: add new feature' \
	-body          <<-'EOF'
		This commit follows all the rules.

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Bad check parsing test' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'package: add new feature' \
	-body          <<-'EOF'
		- item 0
		- item 1
		- item 2
		- item 3
		- item 4

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Revert commit' \
	-expected      '0 0 0 0 0 0 3 3 3 3 3 0 0 0 0 3' \
	-author        'Revert Author' \
	-email         'revert.author@example.com' \
	-subject       "Revert 'package: add new feature'" \
	-body          <<-'EOF'
		This reverts commit.

		Signed-off-by: Revert Author <revert.author@example.com>
	EOF

# shellcheck disable=SC2016
define \
	-test          'Body: malicious body shell injection' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'test: malicious body shell injection' \
	-exists        '/tmp/pwned-by-body' \
	-body          <<-'EOF'
		$(touch /tmp/pwned-by-body)
		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Body: malicious body check injection' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'test: malicious body check injection' \
	-exists        '/tmp/pwned-by-check' \
	-body          <<-'EOF'
		-skip-if is_gt 1 0 && touch /tmp/pwned-by-check
		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Body: missing Signed-off-by but check disabled' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 3 3 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'test: fail on missing signed-off-by' \
	-body          'The Signed-off-by line is missing.' \
	-check-signoff 'false'

define \
	-test          'Body: mismatched Signed-off-by but check disabled' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 3 3 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'test: fail on mismatched signed-off-by' \
	-check-signoff 'false' \
	-body          <<-'EOF'
		The Signed-off-by line is for someone else.

		Signed-off-by: Mismatched Person <mismatched@example.com>
	EOF

define \
	-test          'Bad author email (GitHub noreply)' \
	-expected      '0 0 0 1 0 1 0 0 0 0 0 0 1 0 0 3' \
	-author        'Bad Email' \
	-email         'bad.email@users.noreply.github.com' \
	-subject       'test: fail on bad author email' \
	-body          <<-'EOF'
		Author email is a GitHub noreply address.

		Signed-off-by: Bad Email <bad.email@users.noreply.github.com>
	EOF

define \
	-test          'Subject: starts with whitespace' \
	-expected      '0 0 0 0 0 0 1 1 3 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       ' package: subject starts with whitespace' \
	-body          <<-'EOF'
		This commit should fail.

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Subject: no prefix' \
	-expected      '0 0 0 0 0 0 0 1 3 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'This subject has no prefix' \
	-body          <<-'EOF'
		This commit should fail.

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Subject: capitalized first word' \
	-expected      '0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'package: Capitalized first word' \
	-body          <<-'EOF'
		This commit should fail.

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Subject: ends with a period' \
	-expected      '0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'package: subject ends with a period.' \
	-body          <<-'EOF'
		This commit should fail.

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Subject: too long (hard limit)' \
	-expected      '0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'package: this subject is way too long and should fail the hard limit check of 60 chars' \
	-body          <<-'EOF'
		This commit should fail.

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Body: missing Signed-off-by' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 1 3 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'test: fail on missing signed-off-by' \
	-body          'The Signed-off-by line is missing.'

define \
	-test          'Body: mismatched Signed-off-by' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 1 3 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'test: fail on mismatched signed-off-by' \
	-body          <<-'EOF'
		The Signed-off-by line is for someone else.

		Signed-off-by: Mismatched Person <mismatched@example.com>
	EOF

define \
	-test          'Body: empty' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 0 0 1 3 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'test: fail on empty body' \
	-body          'Signed-off-by: Good Author <good.author@example.com>'

define \
	-test          'Author name is a single word' \
	-expected      '0 0 2 0 2 0 0 0 0 0 0 0 0 0 0 3' \
	-author        'Nickname' \
	-email         'nickname@example.com' \
	-subject       'test: warn on single-word author name' \
	-body          <<-'EOF'
		Author name is a single word.

		Signed-off-by: Nickname <nickname@example.com>
	EOF

define \
	-test          'Subject: too long (soft limit)' \
	-expected      '0 0 0 0 0 0 0 0 0 0 2 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'package: this subject is long and should trigger a warning' \
	-body          <<-'EOF'
		This commit should warn on subject length.

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Body: line too long' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 0 0 0 2 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'test: warn on long body line' \
	-body          <<-'EOF'
		This line in the commit body is extremely long and should definitely exceed the seventy-five character limit imposed by the check script.

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Body: line almost too long' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'test: pass on not too long body line' \
	-body          <<-'EOF'
		This line in the commit body is almost too long and shouldn't fail the test

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Exception: dependabot' \
	-expected      '0 0 3 3 3 3 3 3 3 3 3 3 3 0 3 3' \
	-author        'dependabot[bot]' \
	-email         'dependabot[bot]@users.noreply.github.com' \
	-subject       'CI: bump something from 1 to 2' \
	-no-dependabot 'true' \
	-body          <<-'EOF'
		This commit should skip most tests.
	EOF

define \
	-test          'No exception: dependabot' \
	-expected      '0 0 2 1 2 1 0 0 0 0 0 1 3 0 0 3' \
	-author        'dependabot[bot]' \
	-email         'dependabot[bot]@users.noreply.github.com' \
	-subject       'CI: bump something from 1 to 2' \
	-body          <<-'EOF'
		This commit should fail most tests.
	EOF

define \
	-test          'Exception: weblate' \
	-expected      '0 0 3 3 3 3 3 3 3 3 3 3 3 0 3 3' \
	-author        'Hosted Weblate' \
	-email         'hosted@weblate.org' \
	-subject       'Translated using Weblate (English)' \
	-no-weblate    'true' \
	-body          <<-'EOF'
		This commit should skip most tests.
	EOF

define \
	-test          'No exception: weblate' \
	-expected      '0 0 0 0 0 0 0 1 3 0 0 1 3 0 0 3' \
	-author        'Hosted Weblate' \
	-email         'hosted@weblate.org' \
	-subject       'Translated using Weblate (English)' \
	-body          <<-'EOF'
		This commit should fail most tests.
	EOF

define \
	-test          'Merge commit' \
	-expected      '0 1' \
	-author        'Merge Author' \
	-email         'merge.author@example.com' \
	-subject       'feat: add something to be merged' \
	-body          'This commit will be part of a merge.' \
	-merge         1

define \
	-test          'PR from master' \
	-expected      '1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'package: add new feature' \
	-head-branch   'master' \
	-body          <<-'EOF'
		This commit follows all the rules but PR doesn't.

		Signed-off-by: Good Author <good.author@example.com>
	EOF



define \
	-test          'Feature branch check disabled' \
	-expected      '3 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'package: add new feature' \
	-check-branch  'false' \
	-body          <<-'EOF'
		This commit follows all the rules, check is disabled.

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Feature branch check enabled, PR from main fails' \
	-expected      '1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'package: add new feature' \
	-check-branch  'true' \
	-head-branch   'main' \
	-body          <<-'EOF'
		This commit is from main branch and should fail.

		Signed-off-by: Good Author <good.author@example.com>
	EOF

define \
	-test          'Feature branch check enabled, PR from feature branch passes' \
	-expected      '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3' \
	-author        'Good Author' \
	-email         'good.author@example.com' \
	-subject       'package: add new feature' \
	-check-branch  'true' \
	-head-branch   'feature/new-thing' \
	-body          <<-'EOF'
		This commit is from a feature branch and should pass.

		Signed-off-by: Good Author <good.author@example.com>
	EOF

cleanup() {
	if [ -d "$REPO_DIR" ]; then
		[ -z "$PARALLEL_WORKER" ] && echo "Cleaning up temporary directory '$REPO_DIR'"
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

	local expected_results
	read -r -a expected_results <<< "$expected_results_str"

	[ "$merge" = 1 ] && git switch "$BASE_BRANCH" >/dev/null 2>&1
	commit "$author" "$email" "$subject" "$body" >/dev/null
	[ "$merge" = 1 ] \
		&& git switch "$HEAD_BRANCH" >/dev/null 2>&1 \
		&& git merge --no-ff "$BASE_BRANCH" -m "Merge branch '$BASE_BRANCH' into '$HEAD_BRANCH'" >/dev/null 2>&1

	set +e
	local raw_output
	raw_output=$("$CHECKER_SCRIPT" "$REPO_DIR" 2>&1)
	local exit_code=$?
	set -e

	local fail=0
	local injection_failed=0
	if [ -n "$injection_file" ] && [ -f "$injection_file" ]; then
		fail=1
		injection_failed=1
		status_fail "$description"
		echo "       Injection test failed: file '$injection_file' was created."
		rm -f "$injection_file"
	fi

	local expect_failure=0
	for res in "${expected_results[@]}"; do
		if [ "$res" = 1 ]; then
			expect_failure=1
			break
		fi
	done

	local output
	if [ "$expect_failure" = 1 ]; then
		if [ "$exit_code" = 0 ]; then
			fail=1
			output+=$'\e[1;31mExpected test failure, but got exit code 0\e[0m\n\n'
		fi
	elif [ "$exit_code" != 0 ]; then
		fail=1
		output+=$'\e[1;31mExpected test success, but got exit code '"$exit_code"$'\e[0m\n\n'
	fi

	output+=$'Output:\n\n'

	local line
	local check_idx=0
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

	if [ "$fail" = 0 ]; then
		status_pass "$description"
		if [ "$VERBOSE" = 'true' ]; then
			# shellcheck disable=SC2001
			sed 's/^/       /' <<< "$output"
		fi
		return 0
	else
		[ "$injection_failed" = 0 ] && status_fail "$description"
		# shellcheck disable=SC2001
		sed 's/^/       /' <<< "$output"
		return 1
	fi
}

run_worker() {
	local idx="$1"
	local base_dir="$2"
	local repo_dir="$base_dir/$idx"

	mkdir -p "$repo_dir"
	cd "$repo_dir" || exit 1

	REPO_DIR="$repo_dir"

	git init -b "$BASE_BRANCH" >/dev/null
	git config user.name 'Test User'
	git config user.email 'test.user@example.com'
	commit \
		'Initial Committer' 'initial@example.com'\
		'initial: commit' 'This is the first main commit.' >/dev/null
	git switch -C "$HEAD_BRANCH" >/dev/null 2>&1

	export CHECK_BRANCH="${ENV_CHECK_BRANCH[$idx]}"
	export CHECK_SIGNOFF="${ENV_CHECK_SIGNOFF[$idx]}"
	export EXCLUDE_DEPENDABOT="${ENV_EXCLUDE_DEPENDABOT[$idx]}"
	export EXCLUDE_WEBLATE="${ENV_EXCLUDE_WEBLATE[$idx]}"
	export HEAD_BRANCH="${ENV_HEAD_BRANCH[$idx]}"
	export PARALLEL_WORKER=true

	local output
	output=$(run_test \
		"${DESCRIPTIONS[$idx]}" \
		"${EXPECTED_RESULTS[$idx]}" \
		"${AUTHORS[$idx]}" \
		"${EMAILS[$idx]}" \
		"${SUBJECTS[$idx]}" \
		"${BODIES[$idx]}" \
		"${MERGES[$idx]}" \
		"${INJECTIONS[$idx]}")
	local res=$?

	echo "$output" > "$base_dir/$idx.log"

	if [ "$res" = 0 ]; then
		touch "$base_dir/$idx.pass"
	else
		touch "$base_dir/$idx.fail"
	fi

	return "$res"
}

main() {
	local worker_idx worker_base
	while [ $# -gt 0 ]; do
		case "$1" in
			--base)        worker_base="$2";  shift 2; ;;
			--idx)         worker_idx="$2";   shift 2; ;;
			-v|--verbose)  VERBOSE='true';    shift;   ;;
			*)             REPO_DIR="${1:-}"; break;   ;;
		esac
	done
	export VERBOSE

	if [ -n "$worker_idx" ] && [ -n "$worker_base" ]; then
		run_worker "$worker_idx" "$worker_base"
		exit $?
	fi

	if [ -z "$REPO_DIR" ]; then
		REPO_DIR=$(mktemp -d)
		echo "Using temporary directory '$REPO_DIR'"
	else
		if [ -d "$REPO_DIR" ]; then
			echo "Test repository '$REPO_DIR' already exists" >&2
			exit 1
		fi
		mkdir "$REPO_DIR"
	fi

	echo $'\nStarting test suite\n'

	local self
	self=$(readlink -f "$0")

	# Run tests in parallel in the background
	(
		seq 0 $((${#DESCRIPTIONS[@]} - 1)) |
		xargs -P "$MAX_JOBS" -I {} "$self" ${VERBOSE:+--verbose} --idx {} --base "$REPO_DIR" || true; \
		touch "$REPO_DIR/.done"
	) >/dev/null 2>&1 &
	local pid=$!

	# Display results in order as they become available
	for idx in "${!DESCRIPTIONS[@]}"; do
		local log_file="$REPO_DIR/$idx.log"
		local wait_count=0
		while [ ! -f "$log_file" ]; do
			if [ -f "$REPO_DIR/.done" ] || [ "$wait_count" -ge "$MAX_TEST_WAIT" ]; then
				status_fail "${DESCRIPTIONS[$idx]}"
				err "       Test timed out"
				continue 2
			fi
			wait_count=$((wait_count + 1))
			sleep 0.1
		done

		[ -f "$log_file" ] && cat "$log_file"
	done

	wait "$pid" || true

	local pass_count fail_count test_count
	pass_count=$(find "$REPO_DIR" -name "*.pass" | wc -l)
	fail_count=$(find "$REPO_DIR" -name "*.fail" | wc -l)
	test_count=$((pass_count + fail_count))

	echo $'\nTest suite finished'
	echo "Summary: $pass_count/$test_count tests passed"

	[ "$pass_count" != "$test_count" ] \
		&& exit 1 \
		|| exit 0
}

main "$@"
