"""Exercise the real router installer with isolated apk/opkg command doubles."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('assets/router/install_packages.sh')
sys.argv = sys.argv[:1]
STUB = r'''#!/bin/sh
case "$1" in
  update) echo 'updating feeds' >&2; exit "${UPDATE_CODE:-0}";;
  info) grep -qx "$3" "$STATE";;
  status) grep -qx "$2" "$STATE" && echo 'Status: install user installed';;
  search) printf '%s\n' "$AVAILABLE" | grep -qx "$3" && echo "$3-1.0";;
  list) printf '%s\n' "$AVAILABLE" | grep -qx "$2" && echo "$2 - 1.0";;
  add|install)
    shift
    printf '%s\n' "$*" >> "$TRACE"
    [ "${INSTALL_CODE:-0}" = 0 ] || { echo 'kernel ABI mismatch 10' >&2; exit "$INSTALL_CODE"; }
    [ "${SKIP_WRITE:-0}" = 1 ] || printf '%s\n' "$@" >> "$STATE";;
  *) exit 2;;
esac
'''

class InstallerTests(unittest.TestCase):
    def run_case(self, manager, groups, available='', installed='', update=0, install=0, confirm=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stub = root / manager
            stub.write_text(STUB)
            stub.chmod(0o700)
            state = root / 'installed'
            state.write_text(installed)
            trace = root / 'trace'
            env = dict(os.environ, PATH=f'{root}:/usr/bin:/bin', STATE=str(state),
                       TRACE=str(trace), AVAILABLE=available, UPDATE_CODE=str(update), INSTALL_CODE=str(install), SKIP_WRITE='0' if confirm else '1')
            result = subprocess.run(['/bin/sh', str(SCRIPT), *groups], env=env,
                                    text=True, capture_output=True, timeout=10)
            return result, trace.read_text().strip() if trace.exists() else ''

    def test_available_alternative_only(self):
        for pm in ['apk', 'opkg']:
            with self.subTest(pm=pm):
                result, trace = self.run_case(pm, ['openvpn-openssl openvpn-mbedtls'], 'openvpn-mbedtls')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(trace, 'openvpn-mbedtls')

    def test_installed_requirements_do_not_need_feeds(self):
        for pm in ['apk', 'opkg']:
            result, trace = self.run_case(pm, ['openvpn-openssl openvpn-mbedtls'], installed='openvpn-openssl\n', update=17)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(trace, '')

    def test_missing_package_is_explicit(self):
        for pm in ['apk', 'opkg']:
            result, trace = self.run_case(pm, ['forkop'])
            self.assertEqual(result.returncode, 4)
            self.assertIn('configured', result.stderr)
            self.assertEqual(trace, '')

    def test_feed_failure_is_not_retried_with_another_manager(self):
        for pm in ['apk', 'opkg']:
            result, trace = self.run_case(pm, ['wireguard-tools'], 'wireguard-tools', update=17)
            self.assertEqual(result.returncode, 17)
            self.assertEqual(trace, '')

    def test_install_failure_keeps_exit_code_and_log(self):
        for pm in ['apk', 'opkg']:
            result, _ = self.run_case(pm, ['kmod-wireguard'], 'kmod-wireguard', install=18)
            self.assertEqual(result.returncode, 18)
            self.assertIn('kernel ABI mismatch 10', result.stderr)

    def test_all_required_groups_are_resolved_before_install(self):
        for pm in ['apk', 'opkg']:
            result, trace = self.run_case(pm, ['kmod-wireguard', 'wireguard-tools'], 'wireguard-tools')
            self.assertEqual(result.returncode, 4)
            self.assertEqual(trace, '')

    def test_zero_exit_without_installed_packages_is_not_success(self):
        for pm in ['apk', 'opkg']:
            result, _ = self.run_case(pm, ['wireguard-tools'], 'wireguard-tools', confirm=False)
            self.assertEqual(result.returncode, 5)
            self.assertIn('could not be verified', result.stderr)

    def test_invalid_names_do_not_start_package_manager(self):
        result, trace = self.run_case('apk', ['openvpn;reboot'])
        self.assertEqual(result.returncode, 2)
        self.assertEqual(trace, '')

if __name__ == '__main__':
    unittest.main()
