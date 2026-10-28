#!/usr/bin/env python3
"""Trusted-main CN artifact gates and isolated SDK signing; never run app source.

Secrets are read only by the explicit sign subcommand. No command publishes a
release or changes GitHub configuration. Source archives are never extracted.
"""
import argparse
import base64
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

spec = importlib.util.spec_from_file_location('cn_release', Path(__file__).with_name('android-cn-release.py'))
cn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cn)
ENVIRONMENT = 'android-cn-release'


def validate_protection(environment, policies):
    cn.require(environment.get('name') == ENVIRONMENT and isinstance(environment.get('id'), int), 'Missing signing environment')
    rules = [r for r in environment.get('protection_rules', []) if r.get('type') == 'required_reviewers']
    cn.require(len(rules) == 1 and rules[0].get('prevent_self_review') is True,
               'Signing requires enforced reviewers and prevention of self-review')
    reviewers = rules[0].get('reviewers')
    cn.require(isinstance(reviewers, list) and len(reviewers) > 0 and all(
        r.get('type') in ('User', 'Team') and isinstance(r.get('reviewer', {}).get('id'), int) for r in reviewers),
        'Required signing reviewers are missing or malformed')
    cn.require(environment.get('deployment_branch_policy') == {'protected_branches': False, 'custom_branch_policies': True},
               'Signing must use an explicit main-only deployment policy')
    branches = policies.get('branch_policies', [])
    cn.require(policies.get('total_count') == 1 and len(branches) == 1
               and branches[0].get('name') == 'main' and branches[0].get('type') == 'branch',
               'Signing environment must permit exactly the main branch, with no wildcard or tag rules')
    return environment['id']


def preflight(args):
    cn.require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repository), 'Invalid repository')
    base = f'https://api.github.com/repos/{args.repository}/environments/{ENVIRONMENT}'
    identity = validate_protection(cn.public_json(base), cn.public_json(base + '/deployment-branch-policies?per_page=100'))
    if args.expected_id:
        cn.require(str(identity) == args.expected_id, 'Signing environment was replaced during the run')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'environment_id={identity}\n')


def verify_bundle(args, signed):
    root = args.candidate.resolve()
    cn.validate_sha(args.source_sha)
    cn.validate_sha(args.workflow_sha)
    code = cn.validate_code(args.code)
    expected = json.loads(args.source_record.read_text())
    data = json.loads((root / 'release.json').read_text())
    cn.require(all(data.get(k) == v for k, v in expected.items()), 'Candidate differs from independent source record')
    cn.require(data.get('schemaVersion') == 1 and data.get('applicationId') == cn.PACKAGE and data.get('channel') == 'cn',
               'Wrong CN artifact schema/identity')
    cn.require(data.get('sourceCommit') == args.source_sha and data.get('versionCode') == code
               and data.get('workflowCommit') == args.workflow_sha and data.get('workflowRun') == args.run_url,
               'Candidate source, version or workflow run differs')
    cn.require(data.get('repository') == args.repository and
               data.get('sourceUrl') == f'https://github.com/{args.repository}/tree/{args.source_sha}', 'Wrong source URL')
    version = data.get('versionName', '')
    cn.require(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version), 'Wrong product version')
    cn.require(data.get('tag') == f'android-cn-v{version}-{code}', 'Wrong release tag')
    cn.require(data.get('licenseAudience') == cn.PACKAGE and data.get('licensePublicKeySpkiSha256') == cn.TRUST,
               'Candidate public trust differs')
    cn.require(data.get('signingStatus') == ('verified' if signed else 'unsigned-do-not-distribute')
               and data.get('signingCertificateSha256') == (cn.CERTIFICATE if signed else None), 'Wrong signing status')
    stem = f'DoneAt-Android-CN-{version}-{code}'
    apk_name = stem + ('.apk' if signed else '.unsigned.apk')
    artifact_names = {apk_name, f'{stem}-mapping.txt', f'{stem}-source.tar.gz'}
    expected_files = artifact_names | {'release.json', 'RELEASE.md', 'SHA256SUMS'}
    cn.require(root.is_dir() and {p.name for p in root.iterdir()} == expected_files
               and all(p.is_file() and not p.is_symlink() for p in root.iterdir()), 'Unexpected candidate files or symlinks')
    cn.require(set(data.get('artifacts', {})) == artifact_names, 'Unexpected artifact hash keys')
    cn.require(all(re.fullmatch(r'[0-9a-f]{64}', value) and cn.digest(root / name) == value
                   for name, value in data['artifacts'].items()), 'Artifact checksum mismatch')
    sums = {}
    for line in (root / 'SHA256SUMS').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9_.-]+)', line)
        cn.require(match and match[2] not in sums, 'Malformed or duplicate checksum entry')
        sums[match[2]] = match[1]
    cn.require(set(sums) == expected_files - {'SHA256SUMS'} and
               all(cn.digest(root / name) == value for name, value in sums.items()), 'Candidate checksum mismatch')
    apk = root / apk_name
    cn.verify_manifest(cn.run(str(args.build_tools / 'aapt'), 'dump', 'badging', str(apk)), data)
    cn.run(str(args.build_tools / 'zipalign'), '-c', '-p', '4', str(apk))
    if signed:
        cn.verify_signature(cn.run(str(args.build_tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)))
        cn.require(re.fullmatch(r'[0-9a-f]{64}', data.get('unsignedApkSha256', '')), 'Missing unsigned source APK digest')
    else:
        result = subprocess.run([str(args.build_tools / 'apksigner'), 'verify', str(apk)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        cn.require(result.returncode != 0, 'Expected unsigned APK')
    return data, apk


def sign(args):
    data, unsigned_apk = verify_bundle(args, signed=False)
    for name in ('CN_KEYSTORE_BASE64', 'CN_STORE_PASSWORD', 'CN_KEY_ALIAS', 'CN_KEY_PASSWORD'):
        cn.require(bool(os.environ.get(name)), 'Missing independent CN signing secret')
    args.output.mkdir(parents=True, exist_ok=False)
    signed_apk = args.output / unsigned_apk.name.replace('.unsigned.apk', '.apk')
    # Only trusted Android SDK binaries execute with these secrets. No app
    # source is checked out, loaded, imported, extracted or executed here.
    with tempfile.TemporaryDirectory(prefix='cn-sign-', dir=os.environ.get('RUNNER_TEMP')) as temporary:
        store = Path(temporary) / 'upload.jks'
        fd = os.open(store, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'wb') as output:
            output.write(base64.b64decode(os.environ['CN_KEYSTORE_BASE64'], validate=True))
        env = dict(os.environ)
        env.pop('CN_KEYSTORE_BASE64', None)
        command = [str(args.build_tools / 'apksigner'), 'sign', '--ks', str(store),
                   '--ks-key-alias', os.environ['CN_KEY_ALIAS'], '--ks-pass', 'env:CN_STORE_PASSWORD',
                   '--key-pass', 'env:CN_KEY_PASSWORD', '--v4-signing-enabled', 'false',
                   '--out', str(signed_apk.resolve()), str(unsigned_apk)]
        subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    cn.verify_signature(cn.run(str(args.build_tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(signed_apk)))
    cn.verify_manifest(cn.run(str(args.build_tools / 'aapt'), 'dump', 'badging', str(signed_apk)), data)
    for name in data['artifacts']:
        if name != unsigned_apk.name:
            shutil.copyfile(args.candidate / name, args.output / name)
    data.update(signingStatus='verified', signingCertificateSha256=cn.CERTIFICATE,
                unsignedApkSha256=cn.digest(unsigned_apk),
                artifacts={p.name: cn.digest(p) for p in sorted(args.output.iterdir())})
    (args.output / 'release.json').write_text(json.dumps(data, indent=2) + '\n')
    (args.output / 'RELEASE.md').write_text(
        f'# DoneAt Android CN {data["versionName"]} ({data["versionCode"]})\n\n'
        f'Package: `{cn.PACKAGE}`. Independent activation-code channel.\n\n'
        f'Corresponding source: [{data["sourceCommit"]}]({data["sourceUrl"]}).\n\n'
        f'APK certificate SHA-256: `{cn.CERTIFICATE}`.\n\n'
        f'Build: {data["workflowRun"]}\n\n'
        'Draft candidate: verify real-device acceptance and matching privacy/support '
        'disclosures before the owner publishes or changes domestic download hosting.\n')
    (args.output / 'SHA256SUMS').write_text(''.join(f'{cn.digest(p)}  {p.name}\n' for p in sorted(args.output.iterdir())))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    pre = commands.add_parser('preflight')
    pre.add_argument('--repository', required=True)
    pre.add_argument('--expected-id', default='')
    for name in ('verify', 'sign'):
        sub = commands.add_parser(name)
        sub.add_argument('--candidate', type=Path, required=True)
        sub.add_argument('--source-record', type=Path, required=True)
        sub.add_argument('--build-tools', type=Path, required=True)
        sub.add_argument('--source-sha', required=True)
        sub.add_argument('--workflow-sha', required=True)
        sub.add_argument('--run-url', required=True)
        sub.add_argument('--repository', required=True)
        sub.add_argument('--code', required=True)
        if name == 'verify':
            sub.add_argument('--signed', action='store_true')
            sub.add_argument('--tag-request', type=Path)
        else:
            sub.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'preflight':
            preflight(args)
        elif args.command == 'sign':
            sign(args)
        else:
            data, _ = verify_bundle(args, args.signed)
            if args.tag_request:
                cn.require(args.signed, 'Only a signed candidate may create a source tag request')
                args.tag_request.write_text(json.dumps({'ref': 'refs/tags/' + data['tag'], 'sha': data['sourceCommit']}))
                if os.environ.get('GITHUB_OUTPUT'):
                    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
                        output.write(f'tag={data["tag"]}\n')
    except (ValueError, OSError, subprocess.SubprocessError, KeyError, TypeError, AttributeError):
        parser.exit(1, 'CN isolated signing/protection validation failed; no private tool output is printed.\n')


if __name__ == '__main__':
    main()
