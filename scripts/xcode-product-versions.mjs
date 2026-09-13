// Inspect Xcode's serialized build-settings blocks. This supplements the
// global version scan: that scan cannot detect an omitted MARKETING_VERSION.
export function xcodeProductVersionErrors(project, expected, expectedBundles = []) {
  const products = new Map();
  const errors = [];
  for (const [, settings, rawName] of project.matchAll(
    /isa = XCBuildConfiguration;\s*buildSettings = \{([\s\S]*?)\s*\};\s*name = ([^;]+);/g
  )) {
    const bundle = settings.match(/PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);/)?.[1].trim();
    // Test bundles are not uploaded products and currently have no version.
    if (!bundle || /\b(?:TEST_HOST|TEST_TARGET_NAME)\s*=/.test(settings)) continue;
    const name = rawName.trim().replaceAll('"', "");
    const configurations = products.get(bundle) ?? new Set();
    if (configurations.has(name)) errors.push(`${bundle} repeats ${name}`);
    configurations.add(name);
    products.set(bundle, configurations);
    const version = settings.match(/MARKETING_VERSION\s*=\s*([^;]+);/)?.[1].trim();
    if (version !== expected) errors.push(`${bundle} / ${name}: MARKETING_VERSION must be ${expected}, found ${version ?? "missing"}`);
  }
  if (!products.size) errors.push("No shipping product configurations found");
  for (const [bundle, configurations] of products) {
    for (const name of ["Debug", "Release"]) {
      if (!configurations.has(name)) errors.push(`${bundle} has no ${name} configuration`);
    }
  }
  for (const bundle of expectedBundles) {
    if (!products.has(bundle)) errors.push(`Missing shipping product ${bundle}`);
  }
  return errors;
}
