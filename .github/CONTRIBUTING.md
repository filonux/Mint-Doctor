# How to contribute

Thanks for your interest. This guide summarizes the basics so your contribution can be reviewed and accepted quickly.

## Before writing code

- For large changes or ones that alter current behavior, open an issue first (using the feature request template) to discuss the approach before investing time in implementation.
- For small bug fixes or minor improvements, you can go straight to a *pull request*.

## Submitting the Pull Request

1. Fork the repository and create a branch for your change.
2. Keep the main program in a single file, `script/mint-doctor.sh` (a test enforces this). User-facing messages are written in Spanish in the code and translated to English through the catalog in that same file, so add the English translation whenever you add or change a message; the test suite fails if something is left untranslated.
3. Run the checks locally before opening the PR:

   ```bash
   bash tests/run-tests.sh
   shellcheck --severity=warning script/mint-doctor.sh tests/test.sh tests/run-tests.sh
   ```

   Use the wrapper instead of calling `tests/test.sh` directly: a few end-to-end tests run the script as the unprivileged user `nobody`, which needs root and a copy of the repository that user can read. The wrapper takes care of both (it uses `sudo` if you are not root). The suite never applies a real repair; the end-to-end tests always use `--dry-run`.
4. Open the pull request and fill in the template. The CI workflow (ShellCheck and the test suite) runs automatically and has to pass before the change is merged. ShellCheck *errors* fail the build; *warnings* only show up as annotations, but please don't add new ones.

## Reporting bugs or proposing ideas

Use the repository's issue templates; they open automatically when you create a new one. The more context (Mint and Cinnamon versions, exact steps, terminal output), the faster it can be diagnosed.

For security matters, don't open a public issue — see [`SECURITY.md`](SECURITY.md).

## Releases (maintainer)

A release is published by pushing a version tag. Set `SCRIPT_VERSION` in `script/mint-doctor.sh` to the new version first, then:

```bash
git tag v1.2.3
git push origin v1.2.3
```

The release workflow runs the full CI, checks that the tag matches `SCRIPT_VERSION`, and attaches `mint-doctor.sh` and its `SHA256SUMS` to the GitHub release. Tags with a suffix (for example `v1.3.0-rc1`) are published as pre-releases; for those, `SCRIPT_VERSION` must carry the same suffix (`1.3.0-rc1`), because the tag has to match it exactly.
