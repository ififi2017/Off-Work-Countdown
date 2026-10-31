# Source for DoneAt releases

DoneAt's covered source in this revision is available under MPL-2.0:
https://github.com/ififi2017/Off-Work-Countdown
License and scope: LICENSE and LICENSING.md in the same source revision.
Historical MIT releases retain their original terms.

For an official binary, use the source commit linked from its release/build
record, not an assumption that today's main matches the installed app.
GitHub releases include source archives:
https://github.com/ififi2017/Off-Work-Countdown/releases
Android release tags include the version code; desktop tags include the app
version. iOS/Mac App Store builds must be identified by platform, version
and build number because their marketing version may be shared.

If you cannot locate your build's source, email hello@doneat.app with its
platform, version, build number and download channel. No purchase receipt,
purchase token, personal work records or salary is needed to locate source.
Source access is not conditional on buying Plus or creating an account.

## Maintainer release gate

Before distributing a new MPL-based build, retain its complete covered
source at a public immutable commit/tag and record the platform, version,
build number and source URL in the release record (including store-only
builds). The app's existing About/GitHub links lead to this repository and
these source instructions. Do not publish a build whose source cannot be
obtained. Keep source for distributed versions available after main changes.

Web/Desktop and extension builds generate a source notice containing the
build commit and ship it with the license texts. Third-party notices must
also accompany the components that require them. Secret signing keys and
service credentials are not source distribution requirements.

Independent distributors must provide their own corresponding covered source
and notices; linking only to this upstream repository is not sufficient for
their modifications. They may use their own brand and charge for their build.

For a GitHub fork, set `DONEAT_SOURCE_REPOSITORY` to its HTTPS repository URL
when building locally; GitHub Actions uses `GITHUB_REPOSITORY` by default.
Other source hosts must adapt the tree/archive URL format in
`scripts/prepare-license-notices.mjs` to their actual source endpoint.

## Internal TestFlight source record — iOS 3.2.5 (286)

- Channel: internal TestFlight group Test only; no App Store or external beta review submission.
- Corresponding covered source: https://github.com/ififi2017/Off-Work-Countdown/commit/f411442b370beaf73a6a4fda257fadb6d6bb5959
- Source archive: https://github.com/ififi2017/Off-Work-Countdown/archive/f411442b370beaf73a6a4fda257fadb6d6bb5959.tar.gz
- Scope: localized two-line rest-day Timeline header with next-shift countdown/date, and About App filing 沪ICP备2026055302号-2A shown only for system region CN regardless of app language.
- Build recipe: default AirBuild Xcode 27.2, `airbuild-xcode archive -project src-mobile/ios/App/App.xcodeproj -scheme App -archivePath .airbuild/artifacts/DoneAt-3.2.5-286.xcarchive CURRENT_PROJECT_VERSION=286` with managed signing for the app, iPhone widget, Watch app and Watch widgets. All shipping marketing versions are 3.2.5. The untracked worktree manifest overrides build 286 globally; tracked `CURRENT_PROJECT_VERSION=2` retains the Xcode Cloud convention.
- This record identifies the intended artifact, not processing or distribution success; those are verified against App Store Connect after upload. The subsequent record-only commit does not change covered executable source.
