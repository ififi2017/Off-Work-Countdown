export function normalizeCapacitorIOSPackageManifest(source, version) {
  const normalizedDeclaration = `platforms: [.iOS("${version}")]`;
  if (source.includes(normalizedDeclaration)) return source;

  const major = version.split(".")[0];
  const generatedDeclaration = `platforms: [.iOS(.v${major})]`;
  if (!source.includes(generatedDeclaration)) {
    throw new Error(
      `Capacitor Package.swift does not contain ${generatedDeclaration}.`
    );
  }

  return source.replace(generatedDeclaration, normalizedDeclaration);
}
