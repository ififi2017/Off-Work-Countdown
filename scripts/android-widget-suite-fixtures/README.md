# Widget suite scalar oracle

On macOS with Xcode command-line tools:

```sh
npm run generate:android-widget-suite-fixtures
npm run check:android-widget-suite-fixtures
```

The generator compiles the real `WidgetSuiteContract.swift`, and the verbatim
`WeekProgress`, `CalendarProgress` and `LifeFigures` declarations from their iOS
widget files. `main.swift` supplies fixed inputs and prints the Swift results;
it contains no independent implementation or expected answers. Nothing launches
an iOS simulator. Scratch sources, the compiler module cache and executable stay
in a temporary directory and are removed afterward.

The fixture preserves `ffd91597` as its original iOS 3.2.3 reference. Its
`oracle.sourceHashes` identify the actual working sources compiled, the harness
and the generator. `npm test` checks those hashes on every platform, without a
Swift toolchain. A standalone cheap check is also available:

```sh
node scripts/generate-android-widget-suite-fixtures.mjs --check-sources
```

`--check` recompiles and compares the complete generated file. When a source
changes, review which implementation is correct, regenerate on macOS and run
the Kotlin domain tests; never replace expected answers merely to hide a
failure. The JVM fixture tests cover effective work around lunch and overnight
shifts, calendar shares across both daylight-saving transitions, and Life in
UTC and UTC+13/+14. They do not constitute a full composer or device UI oracle.

The declaration extractor is a narrow Swift lexer, not an AST parser. It
requires one exact `nonisolated struct Name {` marker and handles nested braces,
comments and ordinary/raw quoted strings. Future syntax such as regex literals
or nested string interpolation may require updating it. If a scalar acquires
new dependencies, add their real source files and hashes; do not introduce stub
rules. Extraction and Swift compilation fail rather than falling back to
previous answers.
