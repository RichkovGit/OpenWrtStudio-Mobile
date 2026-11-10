#!/usr/bin/env python3
"""Run the production scanner against real Linux /proc without a router."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'lib/services/protocol_service.dart'
SCRIPT = re.search(r"static const scanScript = r'''(.*?)''';", SOURCE.read_text(), re.S)[1]


class ProcessDetection(unittest.TestCase):
    def detect(self, name, *, deleted=False, fallback=False):
        with tempfile.TemporaryDirectory(prefix='ows process scan ') as folder:
            binary = Path(folder) / name
            shutil.copy2('/bin/sleep', binary)
            child = subprocess.Popen([str(binary), '60'])
            try:
                if deleted:
                    binary.unlink()
                env = os.environ.copy()
                if fallback:
                    shim = Path(folder) / 'readlink'
                    shim.write_text('#!/bin/sh\nexit 1\n')
                    shim.chmod(0o755)
                    env['PATH'] = folder + os.pathsep + env['PATH']
                result = subprocess.run(['/bin/sh', '-c', SCRIPT], env=env,
                                        text=True, capture_output=True, timeout=15, check=True)
                processes = result.stdout.split('===PROCS===\n', 1)[1].split('===DONE===', 1)[0]
                return processes.splitlines()
            finally:
                child.terminate()
                child.wait(timeout=5)

    def test_outside_path_with_arguments_and_spaces(self):
        self.assertIn('xray', self.detect('xray'))

    def test_core_alias(self):
        self.assertIn('xray-core', self.detect('xray-core'))

    def test_helper_name_is_not_core(self):
        self.assertNotIn('xray', self.detect('xray-helper'))

    def test_unlinked_running_binary(self):
        self.assertIn('xray', self.detect('xray', deleted=True))

    def test_comm_fallback_without_readlink(self):
        self.assertIn('xray', self.detect('xray', fallback=True))


if __name__ == '__main__':
    unittest.main()
