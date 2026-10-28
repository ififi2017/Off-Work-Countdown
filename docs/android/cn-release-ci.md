# Android CN GitHub release candidate CI

CN is the independent activation-code channel, package `com.rainif.doneat.cn`.
Play remains `com.rainif.doneat` on `release-android.yml`. The new
`release-android-cn.yml` is manual and runs from `main`. Its default produces
an **unsigned, non-distributable Actions artifact**, with read-only permissions
and no signing secrets. Optional `sign` and `draft` inputs add protected isolated
signing and a GitHub Draft Release. Nothing publishes or changes Play/domestic
hosting. Pull requests changing the helper/tests/workflow run the
offline helper regression suite automatically; they never build a release.

## Source and version gate

Provide a **full 40-character lowercase public commit SHA**, not a branch/tag
name. It must be reachable from `origin/main` or have an existing
`android-cn-v*` tag, and contain the actual independent CN implementation.
Unauthenticated GitHub API access confirms the corresponding source is public.
A source revision without CN support fails instead of producing a Play APK.
The CI tooling revision and app source revision are recorded separately.

The historical `android-cn-v3.2.1-5`, `-6` and `-7` snapshots contain CN;
their existence does not port CN into `main`. Resolve a reviewed snapshot's
SHA before dispatch. For a newer product version, first integrate/review CN
and platform parity in the intended new source revision. Do not claim a new
version's CN artifact from an older snapshot.

Pass an explicit independent `version_code` greater than every existing
`android-cn-v*` tag's code, including earlier product versions. CI overrides
Gradle's code and checks the APK's actual identity/version. Check any locally
distributed or unpublished candidates too: Git tags cannot discover those.
Play version codes remain independent.

Set repository **variable** `DONEAT_CN_LICENSE_PUBLIC_KEYS` to the production
public JSON object (`kid -> Base64 RSA SPKI DER`); no secret is required.
The helper pins kid `cn-prod-2026-01`, SPKI DER SHA-256
`b9f8951659ef9951c2e0a55911ff3699483bf6228eb98590626ba3f1c1125c4b`, audience
`com.rainif.doneat.cn`, and API `https://api.doneat.com.cn`.
Never supply the license private key. Trust rotation needs a reviewed pin
update, rather than a manual dispatch override.

## Candidate contents and checks

CI checks product versions and generated strings, runs all four module unit
suites, Debug lint/build and Release lint/R8 build with `doneatChannel=cn`.
The release dependency report rejects Play Billing/Review and prerelease
Compose/Material3. `aapt` checks package, version and absence of debuggability;
the expected unsigned output must not pass signature verification.
Generated Release BuildConfig must contain CN mode and the pinned production
public configuration.

The 30-day candidate artifact includes `.unsigned.apk`, nonempty R8 mapping,
complete `git archive` source tarball, `release.json`, `RELEASE.md`, and
`SHA256SUMS`. The exact source revision must retain `SOURCE.md`, `LICENSE`
and `LICENSING.md`; submodules need explicit future archive support.
JSON records the APK/mapping/source hashes, source URL/SHA, public trust
fingerprints, CI revision and run URL. Its `signingStatus` is
`unsigned-do-not-distribute` and certificate is null. Checksums also cover
the record and notes. Actions artifacts expire and do not satisfy public
source retention for a distributed build.

## Protected isolated signing and GitHub Draft Release

The initial proposed signing workflow was rejected by automatic approval
review because selected source code would execute Gradle with signing secrets,
and environment protection was only documented. The revised design below
addresses those two specific concerns and passed a fresh scoped approval
review for writing the implementation. No workflow was dispatched, key read,
APK signed or release created during implementation.

1. Manual inputs `sign` and `draft` default to false; `draft=true` requires
   `sign=true`. Source tests/build keep read-only permissions and receive only
   public configuration. The build emits an unsigned candidate.
2. A separate, secret-free preflight job checks the **existing** environment
   `android-cn-release` via GitHub's environment/branch-policy APIs. Require
   nonempty required reviewers, an explicit boolean `prevent_self_review`
   setting (either false or true), and exactly one
   deployment rule permitting branch `main`. Missing environment, API failure,
   missing/ambiguous fields, or weaker protection fails closed before any job
   requests that environment; CI never creates/changes protection settings.
3. Only after preflight succeeds may the isolated signing job request that
   protected environment and wait for its reviewer. Recheck protection after
   approval and before the signing step. Checkout **only the main workflow's
   immutable tooling revision**, never the selected app source. Download
   artifacts as inert data; do not run Gradle, npm, source/archive scripts,
   artifact executables, shell fragments, or plugins from the selected source.
4. Trusted helper validates a strict artifact filename whitelist/checksums,
   exact source SHA/version against the independently uploaded source record,
   APK identity/debug status, and unsigned status. It never extracts source
   archives. The only signing command is Android SDK `apksigner` on the APK.
   Restore independent CN keystore/passwords only in that step's environment;
   use temporary mode-0600 files, password environment references, no raw logs,
   and unconditional cleanup. No Play credentials or repository write token.
5. Reverify signer and package after signing, then regenerate the release
   record/checksums for the signed bytes while retaining source/mapping hashes
   and original unsigned APK digest. Upload a distinct signed candidate.
6. An additional opt-in Draft Release job receives `contents:write`, checks
   the signed candidate again, rejects existing release/tag collisions, and
   creates a **new draft** at the exact source SHA with matching assets. It
   never runs selected source, reads signing secrets, publishes the draft, or
   changes domestic hosting. A plain candidate run cannot enter either job.

Environment and branch checks use GitHub's documented read APIs:
[environment protection](https://docs.github.com/en/rest/deployments/environments#get-an-environment)
and [deployment branch policies](https://docs.github.com/en/rest/deployments/branch-policies#list-deployment-branch-policies).
The same owner may dispatch and manually approve a signing run; no second
account is required. Set `prevent_self_review=false` to allow this. An owner
may instead choose true if they want a different reviewer. CI still waits for
the configured environment's manual approval before signing. Configure
protection and independent CN environment
secrets explicitly before opting in; this change does not create secrets or
modify the existing environment. Owner/admin changes to protection during a
run remain outside code enforcement; both API checks must pass.

The four **environment secrets** are `ANDROID_CN_UPLOAD_KEYSTORE_BASE64`,
`ANDROID_CN_UPLOAD_STORE_PASSWORD`, `ANDROID_CN_UPLOAD_KEY_ALIAS`, and
`ANDROID_CN_UPLOAD_KEY_PASSWORD`. `DONEAT_CN_LICENSE_PUBLIC_KEYS` remains a
repository variable because unsigned builds need only its public key material.
The signer job has read-only contents permission, and its only checkout is
`github.sha` from the main workflow, never `inputs.source_sha`.

### Operational status (read-only inspection, 2026-10-29)

The repository currently has only `Preview` and `Production` environments;
both report empty `protection_rules` and null `deployment_branch_policy`.
`android-cn-release` and its independent `ANDROID_CN_UPLOAD_*` secrets are
not configured. Existing `ANDROID_UPLOAD_*` values belong to Play and must
not be reused. A signing dispatch therefore fails its secret-free preflight
before any environment job or signing step. The code/tests do not make this
a live release service.

To activate later, the owner must separately configure the exact environment
and required-reviewer/main-branch protections above, supply those four CN
secrets, confirm the public-key repository variable, and choose a reviewed
immutable source containing CN. Current product `main` has no CN channel, so
a new 3.2.3 CN release also needs source integration first. No environment,
secret, live release, Play configuration or hosting was changed here.

The existing production CN signer certificate SHA-256 is
`2554fa47d4cb553bf22c1d8821769ca2c27381821c65fe68af835a9336bcd41b`.
After signing, verify that exact signer with `apksigner`, retain the signed
APK and matching source/mapping, and regenerate the record/checksums for the
**signed bytes**. `android-cn-release.py package` without `--unsigned` supports
local verification of an already-signed Gradle output; it does not sign or
upload. Keep any signing configuration in owner-only local files using the
selected CN revision's existing `build-android-cn-release.py` procedure.

The opt-in release job uses write permission only for creating a new
`android-cn-v<version>-<code>` tag and **Draft Release** at the exact source SHA.
GitHub's create-ref API atomically rejects an existing tag; the workflow never
forces a tag or replaces release assets. If draft creation fails after the tag
was created, the owner must inspect that partial result before any retry;
normal reruns deliberately reject the existing tag. Public release still requires production
device acceptance, matching disclosures, retained publicly obtainable source,
and the owner's release action. Domestic hosting must copy the verified APK
and preserve its immutable source/checksum mapping. See `SOURCE.md`.

Helper regression tests (no network, signing material or device required):

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_android_cn_*.py' -v
```
