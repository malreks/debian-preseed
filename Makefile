PYTHON ?= python3
.DEFAULT_GOAL := build

.PHONY: build offline profile check check-perl test test-bootstrap test-debconf test-cuda audit validate themes test-isolation post-change-check static-check

# Check before unittest discovery, including newly added test modules.
test-isolation:
	$(PYTHON) -I -B tools/isolation.py

check check-perl test test-bootstrap test-debconf test-cuda audit validate: test-isolation
build:
	$(PYTHON) -B tools/build.py

# Independent bundle: public metadata only; normal products remain untouched.
offline:
	$(PYTHON) -I -B tools/offline.py

# Authored profile generation only; templates and candidate contracts are data.
profile:
	$(PYTHON) -I -B tools/profile.py

check: check-perl
	$(PYTHON) -B tools/check_build.py
	$(PYTHON) -B tools/check_shells.py
	$(PYTHON) -B tools/validate_placeholder_registry.py --report .build/validation/placeholder-registry-coverage.json
check-perl:
	$(PYTHON) -B d-i/debian/tests/audit_codebase.py --perl-only --prepare-suite forky --prepare-family desktop --output .build/validation/perl-syntax.json
test:
	$(PYTHON) -B -m unittest discover -s d-i/debian/tests -p "test_*.py"
test-bootstrap:
	$(PYTHON) -B -m unittest discover -s d-i/debian/tests -p "test_bootstrap_portability.py" -v
test-debconf:
	$(PYTHON) -B -m unittest discover -s d-i/debian/tests -p "test_debconf_protocol.py" -v
test-cuda:
	$(PYTHON) -B -m unittest discover -s d-i/debian/tests -p "test_cuda_legacy_apt.py" -v
audit:
	$(PYTHON) -B d-i/debian/tests/audit_codebase.py --source-only --output .build/validation/audit.json
validate:
	$(PYTHON) -B tools/validate.py

themes:
	$(PYTHON) -I -B tools/themes.py

post-change-check static-check:
	$(PYTHON) -B tools/post_change_check.py
