# Contributing

## The flow

1. Create a branch from `main` named with the pattern `feat/…`, `fix/…`, `docs/…`, `chore/…`, `test/…`, or `ci/…`.
2. Make small commits with imperative messages explaining why.
3. Validate locally with the corresponding pipeline (below).
4. Open a PR to `main` filling in the [template](.github/pull_request_template.md).
5. Merging is squash into `main`; when the PR covers a large change, prefer splitting it into several smaller PRs over one diffuse PR.

Every change lands via PR to `main` — never by direct push.

## Validation before the PR

Follow the [script matrix in PIPELINES.md](PIPELINES.md#script-matrix) to
choose the checks during the work and the mandatory pre-flight for delivery.
The commands and their distribution across the jobs are documented there.

When GitHub Actions does not start, apply the
[CI-unavailable rule](PIPELINES.md#if-ci-cannot-run-no-token-billing-or-runner).

## Shared practices

Follow [the ownership and evolution policy](docs/agent/practices.md). Reusable
improvements enter through a PR to the Elixir Agent Kit and arrive here through
a pinned version. Board-specific contracts stay in `docs/`. Do not edit the
dependency or recreate a local library. `make library` validates the
installation.
