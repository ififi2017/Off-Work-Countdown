"""Offline regression tests for CN release/source identity gates."""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location('cn_release', Path(__file__).with_name('android-cn-release.py'))
cn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cn)


class IdentityTests(unittest.TestCase):
    def test_source_requires_full_immutable_sha(self):
        for value in ('main', 'android-cn-v3.2.1-7', 'a' * 39, 'A' * 40, 'a' * 40 + '\n', 'a;echo bad'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                cn.validate_sha(value)
        self.assertEqual(cn.validate_sha('a' * 40), 'a' * 40)

    def test_android_version_code_bounds(self):
        for value in ('0', '-1', '01', '1.1', '2100000001', '1\n', '1;echo bad'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                cn.validate_code(value)
        self.assertEqual(cn.validate_code('2100000000'), 2100000000)

    def test_trust_rejects_unknown_test_or_replaced_key(self):
        for value in ('{}', '{"test-key":"YQ=="}', '{"cn-prod-2026-01":"YQ=="}', '[]'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                cn.validate_trust(value)

    def test_exact_single_apk_certificate(self):
        valid = f'Signer #1 certificate SHA-256 digest: {cn.CERTIFICATE}\n'
        cn.verify_signature(valid)
        for value in ('', valid.replace(cn.CERTIFICATE, 'a' * 64), valid + valid.replace('#1', '#2')):
            with self.subTest(value=value), self.assertRaises(ValueError):
                cn.verify_signature(value)

    def test_manifest_rejects_play_debug_and_wrong_versions(self):
        data = {'versionName': '3.2.3', 'versionCode': 8}
        valid = "package: name='com.rainif.doneat.cn' versionCode='8' versionName='3.2.3'"
        cn.verify_manifest(valid, data)
        for value in (valid.replace('.cn', ''), valid.replace("'8'", "'7'"),
                      valid.replace('3.2.3', '3.2.1'), valid + '\napplication-debuggable'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                cn.verify_manifest(value, data)

    def test_cn_dependency_isolation_and_stable_compose(self):
        cn.verify_dependencies('releaseRuntimeClasspath\nandroidx.compose.material3:material3:1.4.0')
        for value in ('no report', 'releaseRuntimeClasspath\ncom.android.billingclient:billing:9.1.0',
                      'releaseRuntimeClasspath\ncom.google.android.play:review:2.0.2',
                      'releaseRuntimeClasspath\nandroidx.compose.material3:material3:1.5.0-alpha01'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                cn.verify_dependencies(value)


class SourceAndPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'source'
        self.root.mkdir()
        self.android = self.root / 'src-mobile/android'
        self.gradle = self.android / 'app/build.gradle.kts'
        self.gradle.parent.mkdir(parents=True)
        self.gradle.write_text('versionName = "3.2.3"\n// doneatCnUploadStoreFile doneatChannel\n')
        (self.android / 'app/src/cn/kotlin').mkdir(parents=True)
        (self.android / 'app/src/cn/kotlin/.keep').write_text('')
        (self.root / 'package.json').write_text('{"version":"3.2.3"}')
        (self.root / '.gitignore').write_text('build/\n')
        for name in ('SOURCE.md', 'LICENSE', 'LICENSING.md'):
            (self.root / name).write_text(name + '\n')
        for command in (('init', '-q'), ('config', 'user.email', 'test@example.invalid'),
                        ('config', 'user.name', 'Test'), ('add', '.'), ('commit', '-qm', 'Source fixture')):
            cn.run('git', *command, cwd=self.root)
        self.sha = cn.run('git', 'rev-parse', 'HEAD', cwd=self.root)
        cn.run('git', 'update-ref', 'refs/remotes/origin/main', self.sha, cwd=self.root)
        self.args = argparse.Namespace(source=self.root, sha=self.sha, code='8',
                                       repository='example/source', output=self.base / 'source-record.json')
        self.api = patch.object(cn, 'public_json', side_effect=[{'private': False}, {'sha': self.sha}])
        self.api.start()
        self.addCleanup(self.api.stop)

    def prepare(self):
        cn.prepare(self.args)
        return json.loads(self.args.output.read_text())

    def test_public_source_record_maps_exact_revision(self):
        data = self.prepare()
        self.assertEqual(data['sourceCommit'], self.sha)
        self.assertEqual(data['tag'], 'android-cn-v3.2.3-8')
        self.assertTrue(data['sourceUrl'].endswith('/tree/' + self.sha))

    def test_dirty_source_is_rejected(self):
        self.gradle.write_text('modified')
        with self.assertRaisesRegex(ValueError, 'clean'):
            self.prepare()

    def test_checkout_mismatch_is_rejected(self):
        self.args.sha = 'f' * 40
        with self.assertRaisesRegex(ValueError, 'match'):
            self.prepare()

    def test_unknown_history_is_rejected(self):
        cn.run('git', 'update-ref', '-d', 'refs/remotes/origin/main', cwd=self.root)
        with self.assertRaisesRegex(ValueError, 'main'):
            self.prepare()

    def test_existing_cn_tag_can_supply_historical_source(self):
        cn.run('git', 'update-ref', '-d', 'refs/remotes/origin/main', cwd=self.root)
        cn.run('git', 'tag', 'android-cn-v3.2.1-7', cwd=self.root)
        self.assertEqual(self.prepare()['versionCode'], 8)

    def test_cn_code_cannot_reuse_existing_release_tag(self):
        cn.run('git', 'tag', 'android-cn-v3.2.1-8', cwd=self.root)
        with self.assertRaisesRegex(ValueError, 'exceed'):
            self.prepare()

    def test_private_repository_is_not_corresponding_public_source(self):
        with patch.object(cn, 'public_json', return_value={'private': True}):
            with self.assertRaisesRegex(ValueError, 'public'):
                self.prepare()

    def test_public_api_commit_must_match_exact_sha(self):
        with patch.object(cn, 'public_json', side_effect=[{'private': False}, {'sha': 'a' * 40}]):
            with self.assertRaisesRegex(ValueError, 'retrievable'):
                self.prepare()

    def test_play_only_source_fails_closed(self):
        self.gradle.write_text('versionName = "3.2.3"\n')
        cn.run('git', 'add', '.', cwd=self.root)
        cn.run('git', 'commit', '-qm', 'Play only', cwd=self.root)
        self.args.sha = cn.run('git', 'rev-parse', 'HEAD', cwd=self.root)
        cn.run('git', 'update-ref', 'refs/remotes/origin/main', self.args.sha, cwd=self.root)
        with patch.object(cn, 'public_json', side_effect=[{'private': False}, {'sha': self.args.sha}]):
            with self.assertRaisesRegex(ValueError, 'independent CN'):
                self.prepare()

    def package_fixture(self, unsigned):
        data = self.prepare()
        apk = self.android / ('app/build/outputs/apk/release/app-release-unsigned.apk' if unsigned
                              else 'app/build/outputs/apk/release/app-release.apk')
        apk.parent.mkdir(parents=True)
        apk.write_bytes(b'APK exact bytes')
        mapping = self.android / 'app/build/outputs/mapping/release/mapping.txt'
        mapping.parent.mkdir(parents=True)
        mapping.write_text('example mapping')
        self.deps = self.base / 'deps.txt'
        self.deps.write_text('releaseRuntimeClasspath\nandroidx.compose.material3:material3:1.4.0')
        self.keys = {'cn-prod-2026-01': base64.b64encode(b'fixture DER').decode()}
        self.trust = {'cn-prod-2026-01': hashlib.sha256(b'fixture DER').hexdigest()}
        config = self.android / 'app/build/generated/source/buildConfig/release/com/rainif/doneat/BuildConfig.java'
        config.parent.mkdir(parents=True)
        config.write_text('CN_CHANNEL = true;\n' + '\n'.join(
            f'{key} = {json.dumps(value)};' for key, value in {
                'CN_LICENSE_PUBLIC_KEYS': json.dumps(self.keys), 'CN_LICENSE_AUDIENCE': cn.PACKAGE,
                'CN_LICENSE_API': 'https://api.doneat.com.cn'}.items()))
        self.pack = argparse.Namespace(source=self.root, metadata=self.args.output,
            build_tools=self.base / 'tools', dependencies=self.deps, workflow_sha='b' * 40,
            run_url='https://github.com/example/source/actions/runs/1', output=self.base / 'candidate', unsigned=unsigned)
        real_run = cn.run
        def fake_run(*args, **kwargs):
            if args[0].endswith('/apksigner'):
                return f'Signer #1 certificate SHA-256 digest: {cn.CERTIFICATE}'
            if args[0].endswith('/aapt'):
                return "package: name='com.rainif.doneat.cn' versionCode='8' versionName='3.2.3'"
            return real_run(*args, **kwargs)
        self.fake_run = patch.object(cn, 'run', side_effect=fake_run)
        self.fake_run.start()
        self.addCleanup(self.fake_run.stop)
        self.pins = patch.object(cn, 'TRUST', self.trust)
        self.pins.start()
        self.addCleanup(self.pins.stop)
        self.env = patch.dict(os.environ, {'ORG_GRADLE_PROJECT_doneatCnLicensePublicKeys': json.dumps(self.keys),
                              'ORG_GRADLE_PROJECT_doneatCnLicenseAudience': cn.PACKAGE})
        self.env.start()
        self.addCleanup(self.env.stop)
        return data, config

    def assert_candidate(self, unsigned):
        data = json.loads((self.pack.output / 'release.json').read_text())
        self.assertEqual(data['sourceCommit'], self.sha)
        self.assertEqual(data['signingStatus'], 'unsigned-do-not-distribute' if unsigned else 'verified')
        self.assertEqual(data['signingCertificateSha256'], None if unsigned else cn.CERTIFICATE)
        for name, value in data['artifacts'].items():
            self.assertEqual(cn.digest(self.pack.output / name), value)
        for line in (self.pack.output / 'SHA256SUMS').read_text().splitlines():
            value, name = line.split('  ')
            self.assertEqual(cn.digest(self.pack.output / name), value)
        archive = next(self.pack.output.glob('*-source.tar.gz'))
        with tarfile.open(archive) as source:
            names = source.getnames()
            self.assertTrue(any(name.endswith('/SOURCE.md') for name in names))
            self.assertFalse(any('/build/' in name for name in names))

    def test_signed_package_records_verified_bytes_source_and_mapping(self):
        self.package_fixture(False)
        cn.package(self.pack)
        self.assert_candidate(False)

    def test_unsigned_candidate_is_explicitly_non_distributable(self):
        self.package_fixture(True)
        real_subprocess_run = subprocess.run
        def fake_signer(args, **kwargs):
            if str(args[0]).endswith('/apksigner'):
                return subprocess.CompletedProcess(args, 1)
            return real_subprocess_run(args, **kwargs)
        with patch.object(cn.subprocess, 'run', side_effect=fake_signer):
            cn.package(self.pack)
        self.assert_candidate(True)
        self.assertIn('UNSIGNED CANDIDATE', (self.pack.output / 'RELEASE.md').read_text())
        self.assertEqual(len(list(self.pack.output.glob('*.unsigned.apk'))), 1)

    def test_unsigned_mode_rejects_a_valid_signature(self):
        self.package_fixture(True)
        real_subprocess_run = subprocess.run
        def fake_signer(args, **kwargs):
            if str(args[0]).endswith('/apksigner'):
                return subprocess.CompletedProcess(args, 0)
            return real_subprocess_run(args, **kwargs)
        with patch.object(cn.subprocess, 'run', side_effect=fake_signer):
            with self.assertRaisesRegex(ValueError, 'signature'):
                cn.package(self.pack)

    def test_compiled_trust_drift_blocks_package(self):
        _, config = self.package_fixture(False)
        config.write_text(config.read_text().replace('https://api.doneat.com.cn', 'http://127.0.0.1'))
        with self.assertRaisesRegex(ValueError, 'Compiled API'):
            cn.package(self.pack)

    def test_modified_source_blocks_package(self):
        self.package_fixture(False)
        self.gradle.write_text('modified after build')
        with self.assertRaisesRegex(ValueError, 'changed during build'):
            cn.package(self.pack)


if __name__ == '__main__':
    unittest.main()
