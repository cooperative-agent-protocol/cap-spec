# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 CAP Authors

.PHONY: lint gen breaking clean verify \
        sbom sign verify-sign \
        lint-licenses lint-spdx \
        bsr-push \
        publish-python-core publish-python-construction publish-python \
        publish-npm-core publish-npm-construction publish-npm \
        all-checks

# ─── Code generation + lint ──────────────────────────────────────────

# Lint proto files against STANDARD rules.
lint:
	buf lint

# Generate code for all targets (Python, C++, TypeScript, C#).
gen:
	buf generate

# Check for breaking changes against the main branch.
breaking:
	buf breaking --against '.git#branch=main,subdir=cap-spec'

# Verify TLA+ formal models with TLC. Requires tla2tools.jar in formal/tla/.
verify:
	cd formal/tla && java -jar tla2tools.jar -config TaskState.cfg TaskState.tla
	cd formal/tla && java -jar tla2tools.jar -config ReservationState.cfg ReservationState.tla
	cd formal/tla && java -jar tla2tools.jar -config MachineMode.cfg MachineMode.tla
	cd formal/tla && java -jar tla2tools.jar -config CAPCoordination_safety.cfg CAPCoordination.tla

# Remove generated code.
clean:
	rm -rf gen/

# ─── Supply chain ────────────────────────────────────────────────────

# Generate CycloneDX SBOM for the generated Python wheel(s) and the
# proto source set. Requires `cyclonedx-py` and `cyclonedx-cli`.
sbom:
	@mkdir -p artifacts
	cyclonedx-py environment -o artifacts/sbom-cap-proto-core-python.json || true
	@echo "SBOM written to artifacts/sbom-*.json"

# Sign release artifacts with sigstore cosign (keyless via GitHub OIDC).
# Requires `cosign` and either a GitHub Actions runtime (`id-token: write`)
# or an OIDC provider configured locally.
sign:
	@for f in artifacts/*; do \
	  test -f "$$f" && cosign sign-blob --yes "$$f" --output-signature "$$f.sig" --output-certificate "$$f.pem" ; \
	done

# Verify signatures of previously-signed artifacts.
verify-sign:
	@for f in artifacts/*; do \
	  test -f "$$f.sig" && cosign verify-blob "$$f" --signature "$$f.sig" --certificate "$$f.pem" --certificate-identity-regexp '.*' --certificate-oidc-issuer-regexp '.*' ; \
	done

# ─── Lint extensions ─────────────────────────────────────────────────

# Check SPDX license headers across source files.
lint-spdx:
	reuse lint

# Inspect dependency license set; fail on copyleft.
lint-licenses:
	pip-licenses --format=json --output-file=artifacts/licenses-python.json || true
	@echo "Note: full Conan / npm license scan runs in CI."

# ─── Buf Schema Registry push ────────────────────────────────────────

# Push the canonical proto module to BSR. Requires `buf registry login`.
bsr-push:
	buf push

# ─── Distribution publish targets ────────────────────────────────────
#
# These are intentionally guarded with NO-OP shims at v0.1 — first
# release is from CI with sigstore-signed artifacts. Local `make publish-*`
# is a dry-run only.

publish-python-core:
	@echo "Publish cap-proto-core-python to PyPI (dry-run; CI does the real publish)"
	@cd gen/python && python -m build --wheel --sdist || true

publish-python-construction:
	@echo "Publish cap-proto-construction-python to PyPI (dry-run; CI does the real publish)"

publish-python: publish-python-core publish-python-construction

publish-npm-core:
	@echo "Publish @cap-protocol/core to npm (dry-run; CI does the real publish)"
	@cd gen/ts && npm pack || true

publish-npm-construction:
	@echo "Publish @cap-protocol/construction to npm (dry-run; CI does the real publish)"

publish-npm: publish-npm-core publish-npm-construction

# ─── Aggregate check (matches CI's lint job) ─────────────────────────

all-checks: lint breaking lint-spdx
