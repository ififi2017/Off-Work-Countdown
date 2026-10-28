# Android CN 3.2.1 (7) corresponding source

Package: com.rainif.doneat.cn. Production API: api.doneat.com.cn.
Immutable source tag: android-cn-v3.2.1-7. The website release record pins the full corresponding commit.
APK SHA-256: 37e480aa222a5a79ce088cfae473097424d4527c34ce7cde820140aa06b9c9d5
Bytes: 5780656
Signing certificate SHA-256: 2554fa47d4cb553bf22c1d8821769ca2c27381821c65fe68af835a9336bcd41b

Adds foreground update reminders (one check per day, same-version reminder at most once per week), plain-text release notes in update prompts and offline About history, and the refined stable update-status row. Installer download remains user initiated. Existing build 6 users can manually check for this version; automatic reminders become available after installing build 7.

Build with the checked-in Gradle wrapper, JBR21 and Android SDK37, selecting `-PdoneatChannel=cn`. CN default versionCode is 7. Public production keys/audience remain in cn-3.2.1-5-public-build.json. Supply your own signing store through the documented doneatCnUpload properties; official private material is excluded. See scripts/build-android-cn-release.py, SOURCE.md, LICENSE and LICENSING.md. This release does not publish another platform or upload to Google Play.
