SHELL := /usr/bin/env bash

.PHONY: help validate bootstrap apply-incus build-base build-php build-python build-cpp build-typescript build-full build-all local-release

help:
	@printf '%s
' \
	  'make validate          Validate repository syntax and secret hygiene' \
	  'make bootstrap         Install host prerequisites and initialise Incus' \
	  'make apply-incus       Apply project, networks, ACL and profiles' \
	  'make build-php         Build the PHP/Joomla image' \
	  'make build-python      Build the Python image' \
	  'make build-cpp         Build the C/C++ image' \
	  'make build-typescript  Build the TypeScript/browser image' \
	  'make build-full        Build the full mixed-language image' \
	  'make build-all         Build every image variant' \\
	  'make local-release     Build, package, verify and optionally publish locally'

validate:
	./tests/validate-repository.sh

bootstrap:
	./scripts/bootstrap-host.sh

apply-incus:
	./scripts/apply-incus.sh

build-base:
	./scripts/build-image.sh base

build-php:
	./scripts/build-image.sh php

build-python:
	./scripts/build-image.sh python

build-cpp:
	./scripts/build-image.sh cpp

build-typescript:
	./scripts/build-image.sh typescript

build-full:
	./scripts/build-image.sh full

build-all:
	./scripts/build-all-images.sh

local-release:
\t./scripts/local-image-release.sh
