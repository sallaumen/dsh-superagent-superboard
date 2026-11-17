# Harness dependency security

The manifest pins the Harness used by first install and runtime maintenance.
`scripts/agent/alpine` points here. Changing this lock does not update or restart
an already running agent; the owner's runtime maintenance action applies it.

## Temporary picomatch replacement

`@deepseek-ai/dsh-hmr@0.2.1-rc.3` uses `picomatch(ignored)` to build its file
watch exclusion predicate. Upstream `picomatch@4.0.7` is affected by
[CVE-2026-112366 / GHSA-fc5q-39xc-vjpf](https://github.com/advisories/GHSA-fc5q-39xc-vjpf),
with no patched upstream release as of November 17, 2026.

Only that consumer is overridden to the exact npm alias
`npm:@ryotsu/picomatch@4.0.7-a`. The lock records its registry URL and SHA-512
integrity. This is a patched implementation, not an advisory exception:
[source commit 3ab5a762](https://github.com/ryotsu-kankichi/secured-picomatch/commit/3ab5a7627d480259e3d9ca67fbc14c125d374f0e)
removes redundant nested repetition in supported single-branch wildcard
extglobs and treats unsupported complex forms literally. The published package
has no runtime dependencies or install hooks. Its registry signature and
publication attestation were verified with `npm audit signatures`.

The published artifact was compared with upstream 4.0.7. Runtime differences
are confined to `lib/parse.js` and `lib/constants.js`: the security fix plus
globstar/newline, adjacent-star, bracket negation and punctuation fixes.
Captures and unsupported complex extglobs can differ; HMR uses a boolean matcher
with default options, not captures or the safeguard opt-out.

`test/harness/glob_security.test.mjs` installs the exact locked matcher in a
temporary directory, verifies normal watcher exclusions and checks attack
inputs in a disposable process with a five-second timeout. It fails on the
original 4.0.7 artifact. It runs in the frontend checks alongside the unchanged
full `npm audit --audit-level=low`. Installation/network failure fails the test.

This fork is a maintenance obligation: npm audits it under its scoped package
name, so upstream picomatch advisories must also be considered during dependency
review. Return to upstream once a corrected release is published and recognized
by the audit, after rerunning these regressions and the complete project gate.
Do not remove the tests, disable `maxExtglobRecursion`, or raise the audit level
to make an upgrade pass.
