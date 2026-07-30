SHELL := /usr/bin/env bash

.PHONY: help validate ci generate bootstrap apply-incus build build-all local-release

help:
	@printf '%s\n' \
	  'make validate          Validate repository syntax, generated state and security contracts' \
	  'make ci                Run the same repository and package checks as pull-request CI' \
	  'make generate          Regenerate all derived platform files from manifest/images.yaml' \
	  'make bootstrap         Install host prerequisites, Incus and the TTL reaper' \
	  'make apply-incus       Apply restricted project, networks, ACLs and profiles' \
	  'make build IMAGE=php   Build one manifest-defined image' \
	  'make build-all         Build every release-enabled image' \
	  'make local-release     Build, package, verify and optionally publish locally'

validate:
	./tests/validate-repository.sh

ci:
	./tests/validate-repository.sh
	./tests/package-roundtrip.sh

generate:
	python3 ./scripts/generate-platform.py --write

bootstrap:
	./scripts/bootstrap-host.sh

apply-incus:
	./scripts/apply-incus.sh

build:
	@test -n "$(IMAGE)" || { printf 'IMAGE is required (for example: make build IMAGE=php)\n' >&2; exit 2; }
	./scripts/build-image.sh "$(IMAGE)"

build-all:
	./scripts/build-all-images.sh

local-release:
	./scripts/local-image-release.sh
