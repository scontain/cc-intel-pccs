# PCCS image security maintenance

The image uses Intel DCAP_1.27 at the commit recorded in `Dockerfile`. Patches
are applied in filename order. `0003` makes required MySQL TLS fail closed and
enables certificate identity verification for both database connections.
`0004` updates the production dependency lockfile within the upstream manifest's
compatible ranges. `npm ci --omit=dev` installs exactly that lockfile.

The `v1.27.0-security.1` image revision is distinct from the older `v1.27` tag,
so an upgrade cannot reuse its cached layers under `IfNotPresent`.
PR and release builds pull fresh base images, bypass build caches, and apply
runtime OS updates. Both PCCS and the chart's Fluent Bit image are scanned for
fixable high/critical OS and application vulnerabilities before the PCCS image
is pushed. Published images are rescanned daily; failures appear in the
`Published image security` GitHub Actions workflow. No CVE exclusions are used.
Unfixed and lower-severity findings still require triage during dependency
maintenance; the publication gate does not assert that an image has zero CVEs.

As of 2026-10-08, the updated production npm lockfile has no high/critical
advisories. One moderate advisory remains,
[GHSA-hp3w-g68c-fv3c](https://github.com/advisories/GHSA-hp3w-g68c-fv3c), in
`sprintf-js`, reached through Umzug's command-line argument parser. npm counts
four affected entries along this chain. PCCS runs migrations programmatically
with fixed local migration files; its HTTP handlers do not pass user-controlled
format strings to that CLI. There is no patched `sprintf-js` release reported
by the audit. Do not use `npm audit fix --force` to downgrade Umzug from 3.x to
2.x; reassess and update this chain when a compatible fix is available.

For local checks, install `tests/security/requirements.txt` in a virtual
environment and run `python tests/security/test_chart.py` from the repository
root. After building an image, run:

```sh
PCCS_TEST_IMAGE=pccs:local bash tests/security/mysql-integration.sh
```

This creates a disposable MySQL container and verifies authentication,
required CA validation, encrypted MySQL connections, and rejection of an
untrusted CA, mismatched hostname, or plaintext connection. All test containers,
network resources, and generated certificates are removed on exit.
