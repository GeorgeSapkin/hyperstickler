# HyperStickler

Commit & PR formalities checker based on the OpenWrt [submission guidelines](
  https://openwrt.org/submitting-patches#submission_guidelines).

## Rules

- Pull request must come from a feature branch
- Pull request must not include merge commits
- Author name must be either a real name 'firstname lastname' or a
  nickname/alias/handle
- Author email must not be a GitHub noreply email
- Commit(ter) name must be either a real name 'firstname lastname' or a
  nickname/alias/handle
- Commit(ter) email must not be a GitHub noreply email
- Commit subject must not start with whitespace
- Commit subject must start with `<package name or prefix>: `
- Commit subject must start with a lower-case word after the prefix
- Commit subject must not end with a period
- Commit subject must be <= `MAX_SUBJECT_LEN_HARD` (and should be <=
  `MAX_SUBJECT_LEN_SOFT`) characters long. Limits are 60 and 50 by default,
  respectively and are configurable via the `max_subject_len_hard` and
  `max_subject_len_soft` inputs.
- `Signed-off-by` must match author. Enabled via the `check_signoff` input.
- `Signed-off-by` must not be a GitHub noreply email. Enabled via the
  `check_signoff` input.
- Commit message must exist
- Commit message lines should be <= `MAX_BODY_LINE_LEN` characters long. Limit
  is 75 by default and is configurable via the `max_body_line_len` input.
- Commit to stable branch should be marked as cherry-picked

## Inputs

All inputs are optional.

### `check_signoff`

- Check if `Signed-off-by` exists and matches author.
- Default: `false`.

### `exclude_dependabot`

- Exclude commits authored by dependabot from some checks.
- Default: `true`.

### `exclude_weblate`

- Exclude commits authored by Weblate from some checks.
- Default: `false`.

### `feedback_url`

- URL to provide feedback to.
- Default: HyperStickler repository.

### `guideline_url`

- Submission guideline URL used in PR comments.
- Default: https://www.kernel.org/doc/html/latest/process/submitting-patches.html

### `max_body_line_len`

- Max body line length. Longer lines result in a warning.
- Default: 75.

### `max_subject_len_hard`

- Hard max subject line length limit. Longer subjects fails check.
- Default: 60.

### `max_subject_len_soft`

- Soft max subject line length limit. Longer subjects result in a warning.
- Default: 50.

### `post_comment`

- Post summaries to the pull request.
- Default: `false`.

### `warn_on_no_modify`

- Warn when PR edits by maintainers are not allowed. Requires `post_comment` to
  be `true`.
- Default: `false`.

## Permissions

Posting comments requires `pull-requests: write`.

## Example usage

```yaml
name: Formalities
on:
  pull_request_target:

permissions:
  pull-requests: write

jobs:
  formal:
    runs-on: ubuntu-slim
    name: Formalities
    steps:
      - name: Check formalities
        uses: georgesapkin/stickler@main
        with:
          check_signoff: true
          exclude_weblate: true
          post_comment: true
```

## Example output

![Example output](assets/output.png)

## Example status comment

> [!WARNING]
>
> Some formality checks failed.
>
> Consider (re)reading [submissions guidelines](https://www.kernel.org/doc/html/latest/process/submitting-patches.html).

<details>
<summary>Failed checks</summary>

Issues marked with an :x: are failing checks.

### Commit 954a556fa0cd1b174f0d2bff7fbed52438e302e5

- :large_orange_diamond: Commit message lines should be <= 75 characters long

    Actual: line 1 is 137 characters long

    $\textsf{This line in the commit body is extremely long and should definitely exceed\color{red}{ the seventy-five character limit imposed by the check script.}}$

### Commit 4c4e612b830bd8593a5ae086b70c5a10230478bc

- :large_orange_diamond: Commit subject must be <= 60 (and should be <= 50) characters long

    Actual: subject is 58 characters long

    $\textsf{package: this subject is long and should trigger a\color{yellow}{ warning}\color{red}{}}$

### Commit ac60037bfa75d8f0ef78fe180e7f5bd9676ec86b

- :large_orange_diamond: Author name must be either a real name 'firstname lastname' or a nickname/alias/handle

    Actual: Nickname seems to be a nickname or an alias

    Expected: a real name 'firstname lastname'

### Commit a965c8c656ba12c54deb0d73712612a4af874714

- :x: Commit message must exist

### Commit dd7bf7a6e1ee1a4d68ffde6002f9f200e852a6f2

- :x: `Signed-off-by` must match author

    Actual: missing or doesn't match author

    Expected: `Signed-off-by: Good Author <good.author@example.com>`

### Commit 9dc29e73d35bf7e8fe5f9075b64e9d276fba0d72

- :x: `Signed-off-by` must match author

    Actual: missing or doesn't match author

    Expected: `Signed-off-by: Good Author <good.author@example.com>`

### Commit e84b5d73ad52a494dfc509c7aa351b5c796547fd

- :x: Commit subject must be <= 60 (and should be <= 50) characters long

    Actual: subject is 86 characters long

    $\textsf{package: this subject is way too long and should f\color{yellow}{ail the ha}\color{red}{rd limit check of 60 chars}}$

### Commit fbfbc1fb6164d858898d504a7e6a69d539a376a7

- :x: Commit subject must not end with a period

### Commit 13819bbc12f8eb8fd3df842008e66bb6b4bde4f3

- :x: Commit subject must start with a lower-case word after the prefix

### Commit e352d5638f7bb2eccaa14b46f967197d0e2e2110

- :x: Commit subject must start with `<package name or prefix>: `

### Commit d0bdf1f38dc3f7e7eb1c06a813289aed5ed67255

- :x: Author email must not be a GitHub noreply email

    Expected: a real email address

- :x: `Signed-off-by` must not be a GitHub noreply email

    Expected: a real email address

</details>

For more details, see the [full job log](https://github.com/GeorgeSapkin/hyperstickler/actions/runs/20320845251/job/58375970465?pr=1#step:4:1).

<sub>Something broken? Consider [providing feedback](https://github.com/georgesapkin/hyperstickler/issues).</sub>

## Tests

Tests use `/tmp` to create a temporary git repository in. Otherwise an
alternative test path can be passed to the test script that will be created
before running tests and removed afterwards.

```bash
src/test.sh /optional/path/to/test/repo
```

## License

GNU General Public License v2.0 only
