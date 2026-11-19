"""Literal service-name grammar; execute only inside the reviewed private guest."""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import re
import subprocess
import tempfile
import unittest


DEBIAN = Path(__file__).resolve().parents[1]
OWNER = DEBIAN / ('hooks/target/usr/local/lib/desktop/perl5/site_perl/'
                  'labwc-security-action/LabwcSecurityAction/Root.pm.tmpl')


class ServiceNameGrammarTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='perl-service-name-', dir='/workspace')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C',
                            'TMPDIR': str(self.root), 'TMP': str(self.root), 'TEMP': str(self.root)}
        source = OWNER.read_text(encoding='utf-8')
        function = re.search(r'^sub _validate_service_name \{\n.*?^\}', source, re.M | re.S)
        self.assertIsNotNone(function)
        # Execute the actual pure validator without loading the privileged
        # module or its constructor/import graph. The caller value must never
        # contribute characters to the service-name grammar through @_ .
        self.code = ('use strict; use warnings;\n' + function[0] + '\n'
                     'my $name = shift @ARGV;\n'
                     'my $value = eval { _validate_service_name("caller/unsafe!", $name) };\n'
                     'if ($@) { print "rejected\\n"; exit 7; }\n'
                     'print "$value\\n";\n')

    def validate(self, name):
        return subprocess.run(['/usr/bin/perl', '-f', '-e', self.code, '--', name],
                              cwd=self.root, env=self.environment, capture_output=True,
                              text=True, timeout=10, check=False)

    def test_literal_at_and_underscore_remain_valid_service_characters(self):
        for name in ('plain.service', 'worker_name@instance.service', 'worker-a:b.service'):
            with self.subTest(name=name):
                result = self.validate(name)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, name + '\n')
                self.assertEqual(result.stderr, '')

    def test_arguments_cannot_expand_the_service_character_allowlist(self):
        for name in ('bad/name.service', 'bad name.service', 'bad!.service',
                     'bad\nname.service', '../bad.service', 'plain.timer', ''):
            with self.subTest(name=name):
                result = self.validate(name)
                self.assertEqual(result.returncode, 7, result.stderr)
                self.assertEqual(result.stdout, 'rejected\n')
                self.assertEqual(result.stderr, '')

    def test_inspect_service_preserves_unit_names_as_operands(self):
        source = OWNER.read_text(encoding='utf-8')
        functions = []
        for name in ('_validate_service_name', '_exec', '_dispatch'):
            matches = re.findall(r'^sub ' + re.escape(name) + r' \{\n.*?^\}',
                                 source, re.M | re.S)
            self.assertEqual(len(matches), 1, name)
            functions.append(matches[0])
        # Keep the actual validator, dispatcher and argv owner together. The
        # final command sink only records argv and never executes a vendor
        # command, loads the privileged module or contacts a service manager.
        code = r'''use strict; use warnings;
package Fixture::CommandSink;
sub require_executable {
    my ($self, $name) = @_;
    $name eq 'systemd-analyze' or die "unexpected command: $name\n";
    return '/fixture/systemd-analyze';
}
sub exec {
    my ($self, @argv) = @_;
    print join("\0", @argv), "\0";
    return 0;
}
package Fixture::RootDispatch;
sub command { return $_[0]->{command}; }
''' + '\n'.join(functions) + r'''
package main;
my $root = bless {
    command => bless({}, 'Fixture::CommandSink'),
}, 'Fixture::RootDispatch';
exit $root->_dispatch('inspect-service', @ARGV);
'''
        for name in ('-Hhost.service', 'plain.service',
                     'worker_name@instance.service', 'worker-a:b.service'):
            with self.subTest(name=name):
                result = subprocess.run(['/usr/bin/perl', '-f', '-e', code, '--', name],
                                        cwd=self.root, env=self.environment, capture_output=True,
                                        text=True, timeout=10, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.split('\0'),
                                 ['/fixture/systemd-analyze', 'security', '--no-pager',
                                  '--', name, ''])
                self.assertEqual(result.stderr, '')


if __name__ == '__main__':
    unittest.main()
