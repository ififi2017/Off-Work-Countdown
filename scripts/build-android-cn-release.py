#!/usr/bin/env python3
"""Build the CN release candidate using owner-only signing configuration.

Does not install, upload, or print signing configuration. Gradle output is kept
in an owner-only log; inspect it privately if a build fails.
"""
import argparse
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile

FIELDS = {
    'doneatCnUploadStoreFile', 'doneatCnUploadStorePassword',
    'doneatCnUploadKeyAlias', 'doneatCnUploadKeyPassword',
    'doneatCnLicensePublicKeys', 'doneatCnLicenseAudience',
}


def load_config(path):
    # Do not follow a substituted symlink; verify the actual opened file.
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'r', encoding='utf-8') as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError('Configuration must be an owner-owned regular file with mode 0600')
        if info.st_size > 65536:
            raise ValueError('Configuration exceeds size limit')
        config = json.load(source)
    if not isinstance(config, dict) or set(config) != FIELDS:
        raise ValueError('Configuration fields do not match the CN release schema')
    if any(not isinstance(value, str) or not value or '\x00' in value for value in config.values()):
        raise ValueError('Configuration values must be nonempty strings')
    if config['doneatCnLicenseAudience'] != 'com.rainif.doneat.cn':
        raise ValueError('Unexpected CN audience')
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=Path.home() / '.config/doneat/android-cn-signing/release-config.json')
    args = parser.parse_args()
    try:
        config = load_config(args.config.expanduser())
    except (OSError, ValueError, TypeError):
        # JSON parser errors can include input values: never echo exceptions.
        parser.exit(2, 'CN release configuration rejected; check its permissions and required fields.\n')
    env = dict(os.environ)
    for name, value in config.items():
        env['ORG_GRADLE_PROJECT_' + name] = value
    env['ORG_GRADLE_PROJECT_doneatChannel'] = 'cn'
    project = Path(__file__).resolve().parents[1] / 'src-mobile/android'
    fd, log_path = tempfile.mkstemp(prefix='doneat-cn-release-', suffix='.log')
    with os.fdopen(fd, 'w') as log:
        try:
            result = subprocess.run(
                ['./gradlew', '-PdoneatChannel=cn', ':app:assembleRelease', ':app:lintRelease', '--no-daemon'],
                cwd=project, env=env, stdout=log, stderr=subprocess.STDOUT,
            )
        except OSError:
            parser.exit(1, 'Could not start Gradle; check JAVA_HOME and the Android build environment.\n')
    if result.returncode:
        parser.exit(result.returncode, 'CN release build failed. Inspect the private log: ' + log_path + '\n')
    print('CN release build passed. Private log: ' + log_path)
    print('APK: ' + str(project / 'app/build/outputs/apk/release/app-release.apk'))
    print('Verify the APK signature, production trust and source provenance before distribution.')


if __name__ == '__main__':
    main()
