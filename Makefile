PYTHON ?= python3
.DEFAULT_GOAL := build

.PHONY: build offline check test test-bootstrap test-debconf test-cuda audit validate themes test-isolation post-change-check static-check

# Check before unittest discovery, including newly added test modules.
test-isolation:
	$(PYTHON) -I -B tools/isolation.py

check test test-bootstrap test-debconf test-cuda audit validate: test-isolation
build:
	$(PYTHON) -B tools/build.py

# Independent bundle: public metadata only; normal products remain untouched.
offline:
	$(PYTHON) -I -B tools/offline.py

check:
	$(PYTHON) -B tools/check_build.py
	$(PYTHON) -B tools/check_shells.py
test:
	$(PYTHON) -B -m unittest discover -s d-i/debian/tests -p "test_*.py"
test-bootstrap:
	$(PYTHON) -B -m unittest discover -s d-i/debian/tests -p "test_bootstrap_portability.py" -v
test-debconf:
	$(PYTHON) -B -m unittest discover -s d-i/debian/tests -p "test_debconf_protocol.py" -v
test-cuda:
	$(PYTHON) -B -m unittest discover -s d-i/debian/tests -p "test_cuda_legacy_apt.py" -v
audit:
	$(PYTHON) -B d-i/debian/tests/audit_codebase.py --output .build/validation/audit.json
validate:
	$(PYTHON) -B tools/validate.py

themes:
	$(PYTHON) -I -B tools/themes.py

post-change-check static-check:
	$(PYTHON) -B tools/post_change_check.py
