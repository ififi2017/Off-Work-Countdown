# Android CN 3.2.1 (5) corresponding source

Package: com.rainif.doneat.cn. Channel: direct CN APK; production api.doneat.com.cn.
The release is identified by the immutable android-cn-v3.2.1-5 tag and its full commit, not moving main.
APK SHA-256: d10a832cece3a88105aa9bdb9586304fa1779154b452c1092d97e57370ac6d60
Signing certificate SHA-256: 2554fa47d4cb553bf22c1d8821769ca2c27381821c65fe68af835a9336bcd41b

Build using Android Studio JBR21, Android SDK37 and the checked-in Gradle wrapper in src-mobile/android. Select -PdoneatChannel=cn. Supply doneatCnLicensePublicKeys and doneatCnLicenseAudience from cn-3.2.1-5-public-build.json as Gradle properties. Supply your own signing store via the four doneatCnUpload* Gradle properties; official private signing material is deliberately excluded. scripts/build-android-cn-release.py documents the private local configuration schema. Android's default versionCode in this revision is5. See docs/android/environment-lock.md for dependency/toolchain context, and SOURCE.md / LICENSE / LICENSING.md for source terms.

The complete Android source, resources and Gradle files are retained here along with the shared iOS/Shared/Resources assets consumed by the Android build. Other platforms retain the parent revision's state; this source tag does not release those platforms or trigger a Play upload. No private backend code or credentials are included.
