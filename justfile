set shell := ["/bin/sh", "-eu", "-c"]

# List commands.
default:
  @just --list --unsorted

# Format the repository.
fmt:
  nix fmt

# Check formatting and run the script tests.
check:
  nix flake check -L

# Evaluate every output without building anything.
check-eval:
  nix flake check --no-build --all-systems

# Build the example system; needs an aarch64-linux builder.
build:
  nix build -L .#checks.aarch64-linux.build

# Run the script tests directly.
test:
  python3 tests/provision.py scripts/provision.sh

# Lint the provisioning script.
lint:
  shellcheck --shell=bash scripts/provision.sh
