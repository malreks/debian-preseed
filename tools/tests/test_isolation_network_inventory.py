"""Fail-closed namespace inventory parsing, inside the reviewed test image."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from isolation import require_test_isolation
require_test_isolation()

import unittest
from unittest import mock
from types import SimpleNamespace
from isolation import NETWORK_INVENTORY_LIMIT, _has_only_loopback, _private_network_is_loopback
import isolation


HEADERS = (b'Inter-|   Receive                                                |  Transmit\n'
           b' face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n')
ROW = b'    lo: ' + b' '.join([b'0'] * 16) + b'\n'


class PrivateNetworkInventoryTests(unittest.TestCase):
    def test_accepts_only_complete_loopback_kernel_inventory(self):
        self.assertTrue(_has_only_loopback(HEADERS + ROW))
        self.assertTrue(_has_only_loopback(HEADERS + b'lo:\t' + b'\t'.join([b'18446744073709551615'] * 16) + b'\n'))

    def test_rejects_extra_missing_or_malformed_interface_data(self):
        candidates = (HEADERS, HEADERS + ROW + ROW, HEADERS + ROW.replace(b'lo:', b'eth0:'),
                      HEADERS + ROW + ROW.replace(b'lo:', b'eth0:'),
                      HEADERS + b'lo: ' + b' '.join([b'0'] * 15) + b'\n',
                      HEADERS + b'lo: ' + b' '.join([b'0'] * 17) + b'\n',
                      HEADERS + ROW.replace(b'0', b'-1', 1),
                      HEADERS + ROW.replace(b'0', b'1.0', 1),
                      HEADERS + ROW.replace(b'0', b'\xff', 1),
                      HEADERS + ROW.replace(b'lo:', b'lo:extra:'),
                      (HEADERS + ROW).replace(b'\n', b'\r\n'),
                      HEADERS + ROW.rstrip(b'\n'))
        for candidate in candidates:
            with self.subTest(candidate=candidate):
                self.assertFalse(_has_only_loopback(candidate))

    def test_rejects_wrong_headers_and_oversized_input(self):
        for candidate in (b'', HEADERS.replace(b'Receive', b'Unknown') + ROW,
                          HEADERS.replace(b'carrier', b'unknown') + ROW,
                          HEADERS + b' ' * NETWORK_INVENTORY_LIMIT + ROW):
            with self.subTest(length=len(candidate)):
                self.assertFalse(_has_only_loopback(candidate))

    def test_rejects_interface_bytes_from_an_overmounted_filesystem(self):
        stream = mock.MagicMock()
        stream.__enter__.return_value = stream
        stream.read.return_value = HEADERS + ROW
        with mock.patch('isolation.os.open', return_value=55), \
                mock.patch('isolation.os.fdopen', return_value=stream), \
                mock.patch('isolation.os.fstat', return_value=SimpleNamespace(st_dev=11)), \
                mock.patch('isolation.os.stat', return_value=SimpleNamespace(st_dev=22)):
            with self.assertRaisesRegex(SystemExit, 'private procfs'):
                _private_network_is_loopback()
        stream.read.assert_not_called()

    def test_rejects_submounts_that_could_redirect_proc_lookups(self):
        mounts = isolation._mounts()
        mounts['/proc/1/net'] = ('/', 'tmpfs', {'nosuid', 'rw'})
        with mock.patch('isolation._mounts', return_value=mounts):
            with self.assertRaisesRegex(SystemExit, 'submounts below the private procfs'):
                isolation.verify_disposable_image()


if __name__ == '__main__':
    unittest.main()
