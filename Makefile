.PHONY: help setup bootstrap build test test-contracts typecheck lint fmt \
        db-up db-down contracts-build contracts-test contracts-fmt contracts-fmt-check \
        contracts-coverage contracts-snapshot soak fork soak-fork clean purge

SHELL := /bin/bash

help:
	@echo "Penny Stocks monorepo tasks"
	@echo ""
	@echo "  setup             install all JS deps + forge submodules (first-time)"
	@echo "  bootstrap         alias for setup"
	@echo "  build             turbo build all workspaces"
	@echo "  test              turbo test all workspaces"
	@echo "  test-contracts    run forge tests (with fuzz/invariant defaults)"
	@echo "  typecheck         turbo typecheck"
	@echo "  lint              turbo lint"
	@echo "  fmt               prettier write"
	@echo "  db-up             docker compose up postgres (indexer)"
	@echo "  db-down           docker compose down"
	@echo "  contracts-build   forge build (packages/contracts)"
	@echo "  contracts-test    forge test -vvv"
	@echo "  contracts-fmt     forge fmt"
	@echo "  contracts-fmt-check forge fmt --check"
	@echo "  contracts-coverage forge coverage"
	@echo "  contracts-snapshot forge snapshot"
	@echo "  soak              run a bounded accelerated soak (see scripts/soak.sh)"
	@echo "  fork              run fork tests against pinned mainnet fork (requires ARCHIVE_RPC_URL)"
	@echo "  clean             remove build artifacts and node_modules"

FORGE := $(HOME)/.foundry/bin/forge
export PATH := $(HOME)/.foundry/bin:$(PATH)

setup bootstrap:
	pnpm install
	@if [ ! -d "packages/contracts/lib/forge-std" ]; then \
		echo "installing foundry submodules..."; \
		cd packages/contracts && forge install; \
	fi

build:
	pnpm build

test:
	pnpm test

test-contracts: contracts-test

typecheck:
	pnpm typecheck

lint:
	pnpm lint

fmt:
	pnpm format

db-up:
	docker compose -f infra/docker/docker-compose.yml up -d postgres

db-down:
	docker compose -f infra/docker/docker-compose.yml down

contracts-build:
	cd packages/contracts && $(FORGE) build

contracts-test:
	cd packages/contracts && $(FORGE) test -vvv

contracts-fmt:
	cd packages/contracts && $(FORGE) fmt

contracts-fmt-check:
	cd packages/contracts && $(FORGE) fmt --check

contracts-coverage:
	cd packages/contracts && $(FORGE) coverage

contracts-snapshot:
	cd packages/contracts && $(FORGE) snapshot

soak:
	./scripts/soak.sh

soak-local:
	./scripts/soak-local.sh

fork:
	./scripts/fork-test.sh

clean:
	pnpm install --force
	rm -rf packages/*/dist apps/*/dist services/*/dist
	rm -rf node_modules

purge: clean
	rm -rf packages/contracts/lib
	rm -rf .turbo