#!/usr/bin/env sh
set -e

LOG_SCOPE=init
. "$(dirname "$0")/log.sh"
log_enable_error_trap

# Host-side preparation run by `initializeCommand` BEFORE the container is built.
#
# This devcontainer is supported only on a Linux host — i.e. opened through WSL2 (Windows)
# or natively on Linux/macOS — so a single POSIX script with a guaranteed `$HOME` covers
# every case. That keeps the bind-mount path robust (no Windows USERPROFILE/backslash
# guesswork) and the workspace fast (WSL2 ext4 instead of the slow 9p Windows-drive mount).

# Some host shells forward the argument with surrounding quotes; strip them so the folder
# name matches ${localWorkspaceFolderBasename} that the bind mount uses.
REPO_NAME="$1"
REPO_NAME="${REPO_NAME%\"}"
REPO_NAME="${REPO_NAME#\"}"
REPO_NAME="${REPO_NAME%\'}"
REPO_NAME="${REPO_NAME#\'}"

# Per-repo isolated Claude DevContainer state on the host, so containers never read or write
# the host's native ~/.claude. Pre-creating the bind-mount source also stops Docker from
# creating it as root.
TARGET_DIR="$HOME/.claude-devcontainer/$REPO_NAME"
log_step "Preparing host Claude state dir"
if [ ! -d "$TARGET_DIR" ]; then
  mkdir -p "$TARGET_DIR"
  log_ok "Created: $TARGET_DIR"
else
  log_info "Already exists: $TARGET_DIR"
fi

# Ensure .devcontainer/.env exists before the build: devcontainer.json loads it via
# `runArgs: --env-file`, and `docker run --env-file` fails outright if the file is missing.
# Seed it from the committed template; never overwrite an existing .env (personal secrets).
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

log_step "Ensuring .devcontainer/.env exists for --env-file"
if [ ! -f "$ENV_FILE" ]; then
  if [ -f "$ENV_EXAMPLE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    log_warn "Created .devcontainer/.env from .env.example - fill in your secrets, then rebuild."
  else
    : > "$ENV_FILE"
    log_warn "Created empty .devcontainer/.env (no .env.example found)."
  fi
else
  log_info "Already exists: .devcontainer/.env"
fi

log_ok "Host preparation complete"