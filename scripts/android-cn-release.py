#!/usr/bin/env python3
"""Validate immutable CN source and package verified, independently signed APKs.

No signing secrets are read here. Run from the workflow checkout, not the source
checkout being built. This script never uploads, publishes, installs or deploys.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request


PACKAGE = 'com.rainif.doneat.cn'
CERTIFICATE = '2554fa47d4cb553bf22c1d8821769ca2c27381821c65fe68af835a9336bcd41b'
TRUST = {'cn-prod-2026-01': 'b9f8951659ef9951c2e0a55911ff3699483bf6228eb98590626ba3f1c1125c4b'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True, stderr=subprocess.PIPE).strip()


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def validate_sha(value):
    require(re.fullmatch(r'[0-9a-f]{40}', value), 'Source must be a full lowercase 40-character commit SHA')
    return value


def validate_code(value):
    require(re.fullmatch(r'[1-9][0-9]*', value) and int(value) <= 2100000000,
            'versionCode must be a positive Android integer')
    return int(value)


def validate_trust(raw):
    keys = json.loads(raw)
    require(isinstance(keys, dict) and set(keys) == set(TRUST), 'Unexpected production trust key IDs')
    for kid, value in keys.items():
        require(isinstance(value, str), 'Public key must be Base64 SPKI DER')
        material = base64.b64decode(value, validate=True)
        require(hashlib.sha256(material).hexdigest() == TRUST[kid], 'Production trust fingerprint mismatch')
    return keys


def public_json(url):
    # Deliberately unauthenticated: an authenticated checkout does not prove that
    # users can obtain the corresponding source. Never send GITHUB_TOKEN here.
    request = urllib.request.Request(url, headers={'Accept': 'application/vnd.github+json',
                                                  'User-Agent': 'DoneAt-CN-source-gate'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def prepare(args):
    sha = validate_sha(args.sha)
    code = validate_code(args.code)
    require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repository), 'Invalid repository')
    root = args.source.resolve()
    require(run('git', 'rev-parse', 'HEAD', cwd=root) == sha, 'Source checkout does not match requested SHA')
    require(not run('git', 'status', '--porcelain', cwd=root), 'Source checkout must be clean')
    require(not (root / '.gitmodules').exists(), 'Source submodules need an explicit archive implementation')
    tags = run('git', 'tag', '--list', 'android-cn-v*', cwd=root).splitlines()
    previous_codes = [int(match[1]) for tag in tags
                      if (match := re.fullmatch(r'android-cn-v[0-9]+\.[0-9]+\.[0-9]+-([0-9]+)', tag))]
    require(code > max(previous_codes, default=0), 'versionCode must exceed every existing CN release tag')
    tagged = run('git', 'tag', '--points-at', sha, '--list', 'android-cn-v*', cwd=root)
    on_main = subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'origin/main'],
                             cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    require(on_main or tagged, 'Source must belong to main or an existing android-cn-v* tag')
    repo = public_json(f'https://api.github.com/repos/{args.repository}')
    require(repo.get('private') is False, 'Corresponding source repository must be public')
    commit = public_json(f'https://api.github.com/repos/{args.repository}/commits/{sha}')
    require(commit.get('sha') == sha, 'Source commit is not publicly retrievable')
    for name in ('SOURCE.md', 'LICENSE', 'LICENSING.md'):
        require((root / name).is_file(), f'Missing source notice: {name}')
    gradle = (root / 'src-mobile/android/app/build.gradle.kts').read_text()
    require((root / 'src-mobile/android/app/src/cn/kotlin').is_dir()
            and 'doneatCnUploadStoreFile' in gradle and 'doneatChannel' in gradle,
            'Selected source does not implement the independent CN channel; do not build a Play APK')
    version = json.loads((root / 'package.json').read_text())['version']
    require(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version), 'Unexpected product version')
    require(re.search(r'versionName\s*=\s*"' + re.escape(version) + '"', gradle), 'Android version differs from product')
    data = {'schemaVersion': 1, 'channel': 'cn', 'applicationId': PACKAGE,
            'versionName': version, 'versionCode': code, 'sourceCommit': sha,
            'sourceUrl': f'https://github.com/{args.repository}/tree/{sha}',
            'repository': args.repository, 'tag': f'android-cn-v{version}-{code}'}
    args.output.write_text(json.dumps(data, indent=2) + '\n')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            for key in ('tag', 'versionName', 'versionCode'):
                output.write(f'{key}={data[key]}\n')


def verify_signature(output):
    fingerprints = re.findall(r'^Signer #[0-9]+ certificate SHA-256 digest: ([0-9a-fA-F]+)$', output, re.M)
    require([value.lower() for value in fingerprints] == [CERTIFICATE],
            'APK must have exactly the independent production CN signing certificate')


def verify_manifest(output, data):
    match = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", output, re.M)
    require(match and match.groups() == (PACKAGE, str(data['versionCode']), data['versionName']),
            'APK identity/version does not match the release source record')
    require('application-debuggable' not in output, 'Debug APK cannot be distributed')


def verify_dependencies(output):
    require('releaseRuntimeClasspath' in output, 'Missing release dependency report')
    require(not re.search(r'com\.android\.billingclient:|com\.google\.android\.play:review', output),
            'CN release unexpectedly contains Play Billing or Review')
    require(not re.search(r'androidx\.compose[^\s]*:[0-9.]+-(?:alpha|beta|rc)', output),
            'Release requires stable Compose/Material3')


def package(args):
    data = json.loads(args.metadata.read_text())
    validate_sha(data['sourceCommit'])
    validate_sha(args.workflow_sha)
    require(re.fullmatch(r'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/[0-9]+', args.run_url),
            'Invalid workflow run URL')
    keys = validate_trust(os.environ.get('ORG_GRADLE_PROJECT_doneatCnLicensePublicKeys', ''))
    require(os.environ.get('ORG_GRADLE_PROJECT_doneatCnLicenseAudience') == PACKAGE, 'Wrong CN trust audience')
    root = args.source.resolve()
    require(run('git', 'rev-parse', 'HEAD', cwd=root) == data['sourceCommit'], 'Source revision changed during build')
    require(not run('git', 'status', '--porcelain', '--untracked-files=no', cwd=root), 'Tracked source changed during build')
    android = root / 'src-mobile/android'
    apk = android / ('app/build/outputs/apk/release/app-release-unsigned.apk' if args.unsigned
                     else 'app/build/outputs/apk/release/app-release.apk')
    mapping = android / 'app/build/outputs/mapping/release/mapping.txt'
    require(apk.is_file() and mapping.is_file() and mapping.stat().st_size > 0, 'APK and nonempty R8 mapping are required')
    if args.unsigned:
        result = subprocess.run([str(args.build_tools / 'apksigner'), 'verify', str(apk)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        require(result.returncode != 0, 'Unsigned CI candidate unexpectedly has a valid signature')
    else:
        verify_signature(run(str(args.build_tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)))
    verify_manifest(run(str(args.build_tools / 'aapt'), 'dump', 'badging', str(apk)), data)
    verify_dependencies(args.dependencies.read_text())
    # The generated release BuildConfig proves the exact public configuration
    # used by this build, rather than merely recording the runner's variables.
    configs = list((android / 'app/build/generated/source/buildConfig/release').rglob('BuildConfig.java'))
    require(len(configs) == 1, 'Expected one generated release BuildConfig')
    config = configs[0].read_text()
    def constant(name):
        match = re.search(r'\b' + name + r'\s*=\s*("(?:[^"\\]|\\.)*")\s*;', config)
        require(match, f'Missing generated {name}')
        return json.loads(match[1])
    require(re.search(r'CN_CHANNEL\s*=\s*true\s*;', config), 'APK build did not select CN')
    require(json.loads(constant('CN_LICENSE_PUBLIC_KEYS')) == keys, 'Compiled public trust differs')
    require(constant('CN_LICENSE_AUDIENCE') == PACKAGE, 'Compiled audience differs')
    require(constant('CN_LICENSE_API') == 'https://api.doneat.com.cn', 'Compiled API differs')
    out = args.output
    out.mkdir(parents=True, exist_ok=False)
    stem = f'DoneAt-Android-CN-{data["versionName"]}-{data["versionCode"]}'
    files = [(apk, f'{stem}{".unsigned" if args.unsigned else ""}.apk'), (mapping, f'{stem}-mapping.txt')]
    for source, name in files:
        shutil.copyfile(source, out / name)
    archive = out / f'{stem}-source.tar.gz'
    subprocess.run(['git', 'archive', '--format=tar.gz', f'--prefix={stem}-source/',
                    '-o', str(archive.resolve()), data['sourceCommit']], cwd=root, check=True)
    data.update({'signingStatus': 'unsigned-do-not-distribute' if args.unsigned else 'verified',
                 'signingCertificateSha256': None if args.unsigned else CERTIFICATE, 'licenseAudience': PACKAGE,
                 'licensePublicKeySpkiSha256': TRUST, 'workflowCommit': args.workflow_sha,
                 'workflowRun': args.run_url, 'artifacts': {p.name: digest(p) for p in sorted(out.iterdir())}})
    (out / 'release.json').write_text(json.dumps(data, indent=2) + '\n')
    (out / 'RELEASE.md').write_text(
        f'# DoneAt Android CN {data["versionName"]} ({data["versionCode"]})\n\n'
        f'Package: `{PACKAGE}`. Independent activation-code channel.\n\n'
        f'Corresponding source: [{data["sourceCommit"]}]({data["sourceUrl"]}). '
        'The source archive, APK and R8 mapping belong to this exact build.\n\n'
        + ('UNSIGNED CANDIDATE — DO NOT INSTALL OR DISTRIBUTE.\n\n' if args.unsigned else
           f'APK signing certificate SHA-256: `{CERTIFICATE}`.\n\n') +
        f'Build: {args.run_url}\n\n'
        'Draft candidate: verify real-device acceptance and matching privacy/support '
        'disclosures before publishing or updating domestic download hosting.\n')
    (out / 'SHA256SUMS').write_text(''.join(f'{digest(p)}  {p.name}\n' for p in sorted(out.iterdir())))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    pre = commands.add_parser('prepare')
    pre.add_argument('--source', type=Path, required=True)
    pre.add_argument('--sha', required=True)
    pre.add_argument('--code', required=True)
    pre.add_argument('--repository', required=True)
    pre.add_argument('--output', type=Path, required=True)
    pack = commands.add_parser('package')
    pack.add_argument('--source', type=Path, required=True)
    pack.add_argument('--metadata', type=Path, required=True)
    pack.add_argument('--build-tools', type=Path, required=True)
    pack.add_argument('--dependencies', type=Path, required=True)
    pack.add_argument('--workflow-sha', required=True)
    pack.add_argument('--run-url', required=True)
    pack.add_argument('--output', type=Path, required=True)
    pack.add_argument('--unsigned', action='store_true', help='Package an unsigned CI candidate; never distributable')
    args = parser.parse_args()
    try:
        (prepare if args.command == 'prepare' else package)(args)
    except (ValueError, OSError, subprocess.SubprocessError, KeyError, TypeError):
        # Do not echo arbitrary tool/config exceptions into CI logs.
        parser.exit(1, 'CN release validation failed; inspect source/configuration and required artifacts.\n')


if __name__ == '__main__':
    main()
