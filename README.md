# HyperStickler

[![test status](https://github.com/georgesapkin/hyperstickler/actions/workflows/test.yml/badge.svg?branch=main)](
  https://github.com/GeorgeSapkin/hyperstickler/actions/workflows/test.yml?query=branch%3Amain)

Commit & PR formalities checker based on the OpenWrt [submission guidelines](
  https://openwrt.org/submitting-patches#submission_guidelines).

## Rules

- Pull request must come from a feature branch. Configured via the
  `check_branch` input.
- Pull request must not include merge commits.
- Author name must be either a real name 'firstname lastname' or a
  nickname/alias/handle.
- Author email must not be a GitHub noreply email.
- Commit(ter) name must be either a real name 'firstname lastname' or a
  nickname/alias/handle.
- Commit(ter) email must not be a GitHub noreply email.
- Commit subject must not start with whitespace.
- Commit subject must start with `<package name or prefix>: `.
- Commit subject must start with a lower-case word after the prefix.
- Commit subject must not end with a period.
- Commit subject must be <= `MAX_SUBJECT_LEN_HARD` (and should be <=
  `MAX_SUBJECT_LEN_SOFT`) characters long. Limits are 60 and 50 by default,
  respectively and are configurable via the `max_subject_len_hard` and
  `max_subject_len_soft` inputs.
- `Signed-off-by` must match author. Configured via the `check_signoff` input.
- `Signed-off-by` must not be a GitHub noreply email. Configured via the
  `check_signoff` input.
- Commit message must exist.
- Commit message lines should be <= `MAX_BODY_LINE_LEN` characters long. Limit
  is 75 by default and is configurable via the `max_body_line_len` input.
- Commit to stable branch should be marked as cherry-picked.
- Verifies commit signature (GPG/SSH) if present. Missing signatures are ignored, but invalid signatures will cause a failure.
- Modified files must end with a newline. Configured via the `check_trailing_newline` input.
- Modified files must not contain trailing whitespace. Configured via the `check_trailing_whitespace` input.

## Inputs

All inputs are optional.

### `check_branch`

- Check if pull request comes from a feature branch.
- Default: `true`.

### `check_signoff`

- Check if `Signed-off-by` exists and matches author.
- Default: `false`.

### `check_trailing_newline`

- Check if modified files end with a newline.
- Default: `true`.

### `check_trailing_whitespace`

- Check if modified files contain trailing whitespace.
- Default: `true`.

### `exclude_dependabot`

- Exclude commits authored by dependabot from some checks.
- Default: `true`.

### `exclude_weblate`

- Exclude commits authored by Weblate from some checks.
- Default: `false`.

### `feedback_url`

- URL to provide feedback to. If empty, no feedback text will be added to either
  console log or comment.
- Default: HyperStickler repository.

### `guideline_url`

- Submission guideline URL used in PR comments.
- Default: https://www.kernel.org/doc/html/latest/process/submitting-patches.html

### `job_step`

- Job step number that full log link in comment should point to. Otherwise it
  will point to the job itself. Requires `post_comment` to be `true`.

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
        uses: georgesapkin/hyperstickler@main
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

### Commit [57b3864](https://github.com/GeorgeSapkin/hyperstickler/commit/57b3864c7a0ee80a22b697047ee499875c87ada6)

- :x: Commit subject must start with `<package name or prefix>: `
- :x: `Signed-off-by` must match author

    Actual: missing or doesn't match author

    Expected: `Signed-off-by: Hosted Weblate <hosted@weblate.org>`

### Commit [5058449](https://github.com/GeorgeSapkin/hyperstickler/commit/50584490c6ca6342ba49ae6359a6170e0a4551a5)

- :large_orange_diamond: Commit message lines should be <= 75 characters long

    Actual: line 1 is 137 characters long

    $\textsf{This line in the commit body is extremely long and should definitely exceed\color{red}{ the seventy-five character limit imposed by the check script.}}$

### Commit [2e99bff](https://github.com/GeorgeSapkin/hyperstickler/commit/2e99bffd521a723ddb7182fb339cb1d4e760d9c7)

- :large_orange_diamond: Commit subject must be <= 60 (and should be <= 50) characters long

    Actual: subject is 58 characters long

    $\textsf{package: this subject is long and should trigger a\color{yellow}{ warning}\color{red}{}}$

### Commit [fed351d](https://github.com/GeorgeSapkin/hyperstickler/commit/fed351d746be606f7f700521a9204b32ccde08a5)

- :large_orange_diamond: Author name must be either a real name 'firstname lastname' or a nickname/alias/handle

    Actual: Nickname seems to be a nickname or an alias

    Expected: a real name 'firstname lastname'

### Commit [5130080](https://github.com/GeorgeSapkin/hyperstickler/commit/513008085d21c6caed6e8d1f95be86da06bccd72)

- :x: Commit message must exist

### Commit [d13201a](https://github.com/GeorgeSapkin/hyperstickler/commit/d13201afdd96499f8f579192fd488670e98e9300)

- :x: `Signed-off-by` must match author

    Actual: missing or doesn't match author

    Expected: `Signed-off-by: Good Author <good.author@example.com>`

### Commit [5f4c710](https://github.com/GeorgeSapkin/hyperstickler/commit/5f4c7105932e6cac4b87679f97fd9fcfbd1eb5ce)

- :x: `Signed-off-by` must match author

    Actual: missing or doesn't match author

    Expected: `Signed-off-by: Good Author <good.author@example.com>`

### Commit [b26caff](https://github.com/GeorgeSapkin/hyperstickler/commit/b26caffdb7523ad42b29bedd25073e71c4a4a4ae)

- :x: Commit subject must be <= 60 (and should be <= 50) characters long

    Actual: subject is 86 characters long

    $\textsf{package: this subject is way too long and should f\color{yellow}{ail the ha}\color{red}{rd limit check of 60 chars}}$

### Commit [d6ffd3d](https://github.com/GeorgeSapkin/hyperstickler/commit/d6ffd3d20b7ee0b249f9dc6bb29667520899085b)

- :x: Commit subject must not end with a period

### Commit [bb7a6f8](https://github.com/GeorgeSapkin/hyperstickler/commit/bb7a6f82016eac5091b86ebf5178f23957cbd216)

- :x: Commit subject must start with a lower-case word after the prefix

### Commit [0f2c7e8](https://github.com/GeorgeSapkin/hyperstickler/commit/0f2c7e8f796f119c58bcb1be1fd0525757bef8c0)

- :x: Commit subject must start with `<package name or prefix>: `

### Commit [f7d3b13](https://github.com/GeorgeSapkin/hyperstickler/commit/f7d3b1394ad3085c47f704150635793791108ec7)

- :x: Commit subject must not start with whitespace
- :x: Commit subject must start with `<package name or prefix>: `

### Commit [ff3950e](https://github.com/GeorgeSapkin/hyperstickler/commit/ff3950ea1e250508d6a9932ecdd79ec506966b0c)

- :x: Author email must not be a GitHub noreply email

    Expected: a real email address

- :x: `Signed-off-by` must not be a GitHub noreply email

    Expected: a real email address

</details>

For more details, see the [full job log](https://github.com/GeorgeSapkin/hyperstickler/actions/runs/20410211299/job/58645848030?pr=1#step:2:1).

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
