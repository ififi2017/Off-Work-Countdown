# Android CN 3.2.1 (6) corresponding source

Package: com.rainif.doneat.cn. Channel: direct CN APK; production api.doneat.com.cn.
Corresponding source is retained at tag `android-cn-v3.2.1-6`; the public website release record also pins its full commit.

APK SHA-256: 5f6455f5ce44413c55dccbe261973e421727aa07c90583e4e5452c7bb79d672d
Bytes: 5782546
Signing certificate SHA-256: 2554fa47d4cb553bf22c1d8821769ca2c27381821c65fe68af835a9336bcd41b

This release adds manual About-page update checks, the current iOS studio mark, and APP registration 沪ICP备2026055302号-2A. Update checks request only public channel metadata; downloading requires the user's action on the official website. Existing build 5 users must download build 6 once to obtain this feature.

Build with the checked-in Gradle wrapper, Android Studio JBR21 and Android SDK37, selecting `-PdoneatChannel=cn`. Use the public license keys/audience in `cn-3.2.1-5-public-build.json`; production trust and package identity are unchanged. Supply your own signing store through the four `doneatCnUpload*` properties; official private signing material is excluded. `scripts/build-android-cn-release.py` documents local configuration. The CN default versionCode is 6; Play remains unchanged.

The complete covered Android source and shared resources are retained in this revision under the terms in SOURCE.md, LICENSE and LICENSING.md. This source tag does not release other platforms or upload to Play.
