"""No-network/no-real-key tests for protected isolated CN signing."""
import argparse
import base64
import copy
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('cn_signing', Path(__file__).with_name('android-cn-signing.py'))
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)
cn = signing.cn


class ProtectionTests(unittest.TestCase):
    def setUp(self):
        self.environment = {'name': signing.ENVIRONMENT, 'id': 42,
            'protection_rules': [{'type': 'required_reviewers', 'prevent_self_review': True,
                                  'reviewers': [{'type': 'User', 'reviewer': {'id': 8}}]}],
            'deployment_branch_policy': {'protected_branches': False, 'custom_branch_policies': True}}
        self.policies = {'total_count': 1, 'branch_policies': [{'name': 'main', 'type': 'branch'}]}

    def test_actual_protected_environment_passes(self):
        self.assertEqual(signing.validate_protection(self.environment, self.policies), 42)

    def test_owner_may_dispatch_and_manually_approve(self):
        self.environment['protection_rules'][0]['prevent_self_review'] = False
        self.assertEqual(signing.validate_protection(self.environment, self.policies), 42)

    def test_missing_reviewer_or_ambiguous_self_review_policy_fails(self):
        for change in ({'prevent_self_review': None}, {'prevent_self_review': 'false'},
                       {'reviewers': []}, {'reviewers': [{'type': 'User'}]}):
            environment = copy.deepcopy(self.environment)
            environment['protection_rules'][0].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                signing.validate_protection(environment, self.policies)
        with self.assertRaises(ValueError):
            signing.validate_protection({}, self.policies)

    def test_main_wildcards_tags_and_additional_rules_are_rejected(self):
        for policies in ({'total_count': 0, 'branch_policies': []},
                         {'total_count': 1, 'branch_policies': [{'name': '*', 'type': 'branch'}]},
                         {'total_count': 1, 'branch_policies': [{'name': 'main', 'type': 'tag'}]},
                         {'total_count': 1, 'branch_policies': [{'name': 'main'}]},
                         {'total_count': 2, 'branch_policies': [{'name': 'main', 'type': 'branch'}]}):
            with self.subTest(policies=policies), self.assertRaises(ValueError):
                signing.validate_protection(self.environment, policies)
        self.environment['deployment_branch_policy'] = None
        with self.assertRaises(ValueError):
            signing.validate_protection(self.environment, self.policies)

    def test_recreated_environment_does_not_reuse_preflight(self):
        args = argparse.Namespace(repository='example/source', expected_id='41')
        with patch.object(cn, 'public_json', side_effect=[self.environment, self.policies]):
            with self.assertRaisesRegex(ValueError, 'replaced'):
                signing.preflight(args)

    def test_api_error_is_not_treated_as_an_unprotected_environment_creation(self):
        args = argparse.Namespace(repository='example/source', expected_id='')
        with patch.object(cn, 'public_json', side_effect=OSError('404')):
            with self.assertRaises(OSError):
                signing.preflight(args)


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.candidate = self.root / 'unsigned'
        self.candidate.mkdir()
        self.stem = 'DoneAt-Android-CN-3.2.3-8'
        self.source = {'schemaVersion': 1, 'channel': 'cn', 'applicationId': cn.PACKAGE, 'versionName': '3.2.3',
            'versionCode': 8, 'sourceCommit': 'a' * 40, 'sourceUrl': 'https://github.com/example/source/tree/' + 'a' * 40,
            'repository': 'example/source', 'tag': 'android-cn-v3.2.3-8'}
        self.record = self.root / 'source-record.json'
        self.record.write_text(json.dumps(self.source))
        for suffix in ('.unsigned.apk', '-mapping.txt', '-source.tar.gz'):
            (self.candidate / (self.stem + suffix)).write_bytes(suffix.encode())
        self.data = {**self.source, 'signingStatus': 'unsigned-do-not-distribute', 'signingCertificateSha256': None,
            'licenseAudience': cn.PACKAGE, 'licensePublicKeySpkiSha256': cn.TRUST, 'workflowCommit': 'b' * 40,
            'workflowRun': 'https://github.com/example/source/actions/runs/1',
            'artifacts': {p.name: cn.digest(p) for p in self.candidate.iterdir()}}
        self.write_record()
        self.args = argparse.Namespace(candidate=self.candidate, source_record=self.record,
            build_tools=self.root / 'trusted-sdk', source_sha='a' * 40, workflow_sha='b' * 40, code='8',
            run_url='https://github.com/example/source/actions/runs/1', repository='example/source',
            output=self.root / 'signed')
        self.command_log = []
        def sdk_output(*args, **kwargs):
            self.command_log.append(args)
            if args[0].endswith('/aapt'):
                return "package: name='com.rainif.doneat.cn' versionCode='8' versionName='3.2.3'"
            if args[0].endswith('/zipalign'):
                return ''
            if args[0].endswith('/apksigner') and args[1] == 'verify':
                return f'Signer #1 certificate SHA-256 digest: {cn.CERTIFICATE}'
            raise AssertionError('Unexpected executable: ' + str(args))
        self.sdk = patch.object(cn, 'run', side_effect=sdk_output)
        self.sdk.start()
        self.addCleanup(self.sdk.stop)
        self.processes = []
        def sdk_process(args, **kwargs):
            self.processes.append((args, kwargs))
            if args[0].endswith('/apksigner') and args[1] == 'verify':
                return subprocess.CompletedProcess(args, 1)
            if args[0].endswith('/apksigner') and args[1] == 'sign':
                self.store = Path(args[args.index('--ks') + 1])
                self.assertEqual(stat.S_IMODE(self.store.stat().st_mode), 0o600)
                self.assertEqual(self.store.read_bytes(), b'FAKE KEYSTORE')
                self.assertEqual(args[args.index('--ks-pass') + 1], 'env:CN_STORE_PASSWORD')
                self.assertEqual(args[args.index('--key-pass') + 1], 'env:CN_KEY_PASSWORD')
                self.assertNotIn('private-password', ' '.join(args))
                self.assertNotIn('CN_KEYSTORE_BASE64', kwargs['env'])
                Path(args[args.index('--out') + 1]).write_bytes(b'SIGNED APK BYTES')
                return subprocess.CompletedProcess(args, 0)
            raise AssertionError('Selected source must never execute in isolated signing')
        self.process = patch.object(subprocess, 'run', side_effect=sdk_process)
        self.process.start()
        self.addCleanup(self.process.stop)

    def write_record(self):
        (self.candidate / 'release.json').write_text(json.dumps(self.data))
        (self.candidate / 'RELEASE.md').write_text('UNSIGNED')
        sums = self.candidate / 'SHA256SUMS'
        sums.write_text(''.join(f'{cn.digest(p)}  {p.name}\n' for p in sorted(self.candidate.iterdir()) if p != sums))

    def test_inert_candidate_has_exact_source_and_files(self):
        data, apk = signing.verify_bundle(self.args, signed=False)
        self.assertEqual(data['sourceCommit'], self.source['sourceCommit'])
        self.assertEqual(apk.name, self.stem + '.unsigned.apk')

    def test_tampered_binary_is_rejected_before_any_signing(self):
        (self.candidate / (self.stem + '.unsigned.apk')).write_bytes(b'SUBSTITUTED')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            signing.verify_bundle(self.args, signed=False)
        self.assertEqual(self.processes, [])

    def test_source_record_cannot_be_replaced_by_build_metadata(self):
        self.data['sourceCommit'] = 'c' * 40
        self.write_record()
        with self.assertRaisesRegex(ValueError, 'independent source'):
            signing.verify_bundle(self.args, signed=False)

    def test_other_run_or_unsigned_trust_cannot_be_reused(self):
        for field, value in (('workflowRun', 'https://github.com/example/source/actions/runs/2'),
                             ('licensePublicKeySpkiSha256', {}), ('signingStatus', 'verified')):
            original = self.data[field]
            self.data[field] = value
            self.write_record()
            with self.subTest(field=field), self.assertRaises(ValueError):
                signing.verify_bundle(self.args, signed=False)
            self.data[field] = original

    def test_extra_executable_or_symlink_is_rejected_as_data(self):
        extra = self.candidate / 'run.sh'
        extra.write_text('not executed')
        with self.assertRaisesRegex(ValueError, 'files'):
            signing.verify_bundle(self.args, signed=False)
        extra.unlink()
        archive = self.candidate / (self.stem + '-source.tar.gz')
        archive.unlink()
        archive.symlink_to(self.record)
        with self.assertRaisesRegex(ValueError, 'files'):
            signing.verify_bundle(self.args, signed=False)

    def test_checksum_path_traversal_and_duplicate_are_rejected(self):
        sums = self.candidate / 'SHA256SUMS'
        normal = sums.read_text()
        for changed in (normal + 'a' * 64 + '  ../private\n', normal + normal.splitlines()[0] + '\n'):
            sums.write_text(changed)
            with self.assertRaisesRegex(ValueError, 'checksum'):
                signing.verify_bundle(self.args, signed=False)

    def test_signing_executes_only_sdk_and_retains_source_mapping(self):
        with patch.dict(os.environ, {'CN_KEYSTORE_BASE64': base64.b64encode(b'FAKE KEYSTORE').decode(),
                'CN_STORE_PASSWORD': 'private-password', 'CN_KEY_PASSWORD': 'private-password',
                'CN_KEY_ALIAS': 'cn', 'RUNNER_TEMP': str(self.root)}):
            signing.sign(self.args)
        self.assertFalse(self.store.exists())
        self.assertTrue(all(str(args[0]).startswith(str(self.args.build_tools)) for args in self.command_log))
        signed_args = copy.copy(self.args)
        signed_args.candidate = self.args.output
        signed, apk = signing.verify_bundle(signed_args, signed=True)
        self.assertEqual(signed['signingStatus'], 'verified')
        self.assertEqual(signed['unsignedApkSha256'], self.data['artifacts'][self.stem + '.unsigned.apk'])
        self.assertEqual(apk.read_bytes(), b'SIGNED APK BYTES')
        for suffix in ('-mapping.txt', '-source.tar.gz'):
            name = self.stem + suffix
            self.assertEqual(signed['artifacts'][name], self.data['artifacts'][name])
        self.assertFalse(any(p.name.endswith('.unsigned.apk') for p in self.args.output.iterdir()))

    def test_failed_sdk_signing_removes_private_material(self):
        def fail(command, **kwargs):
            if command[1] == 'verify':
                return subprocess.CompletedProcess(command, 1)
            self.store = Path(command[command.index('--ks') + 1])
            raise subprocess.CalledProcessError(1, command, stderr=b'private log')
        with patch.dict(os.environ, {'CN_KEYSTORE_BASE64': base64.b64encode(b'FAKE KEYSTORE').decode(),
                'CN_STORE_PASSWORD': 'private-password', 'CN_KEY_PASSWORD': 'private-password',
                'CN_KEY_ALIAS': 'cn', 'RUNNER_TEMP': str(self.root)}), patch.object(subprocess, 'run', side_effect=fail):
            with self.assertRaises(subprocess.CalledProcessError):
                signing.sign(self.args)
        self.assertFalse(self.store.exists())
        self.assertFalse((self.args.output / 'release.json').exists())


if __name__ == '__main__':
    unittest.main()
