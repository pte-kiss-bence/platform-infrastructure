#!/usr/bin/env sh
set -e

LOG_SCOPE=fix-perms
. "$(dirname "$0")/log.sh"
log_enable_error_trap

# Durable workspace-permission guard for the WHOLE repository.
#
# Some processes in this container run as root (docker-outside-of-docker writes,
# certain CLI/agent tools) and would otherwise create files in the bind-mounted
# workspace owned by root:root — which the `vscode` user (VS Code, Claude, our
# tooling) then cannot write, producing EACCES. Two layers fix this permanently:
#
#   1. Heal   — chown any existing root-owned paths back to vscode.
#   2. Prevent — set a *default* POSIX ACL granting vscode rwx on every repo
#      directory. ext4 stores default ACLs on the host inode, so they survive
#      container restarts/rebuilds AND are inherited by every file/dir created
#      later, even by root mid-session. The access ACL on the same dirs keeps
#      already-present files writable.
#
# node_modules is skipped for speed (large, always vscode-owned). .git is NOT
# skipped: root processes (lint-staged hooks, agent/CLI tools) do write into
# .git/objects, so it needs the same default ACL — otherwise a root-created
# object is unwritable by vscode and `git add` fails with EACCES.
# Idempotent — safe to re-run any time (post-create, or by hand if permissions
# ever break: `sh .devcontainer/fix-permissions.sh`).

REPO="${1:-$(pwd)}"

# ext4 supports ACLs; the `acl` package ships getfacl/setfacl.
if ! command -v setfacl > /dev/null 2>&1; then
  log_step "Installing acl package (setfacl missing)"
  sudo apt-get install -y acl
fi

# 1. Heal existing root-owned paths (skip the huge, always-vscode node_modules).
log_step "Healing root-owned paths under $REPO"
sudo find "$REPO" -path "$REPO/node_modules" -prune -o ! -user vscode -print0 \
  | sudo xargs -0 --no-run-if-empty chown vscode:vscode

# 2. Default + access ACLs on every repo directory (skip only node_modules).
#    Covers .git so root-created git objects inherit vscode rwx and stay writable.
log_step "Applying default ACLs to repo directories"
sudo find "$REPO" -type d -name node_modules -prune -o -type d -print0 \
  | sudo xargs -0 --no-run-if-empty setfacl -m d:u:vscode:rwx -m u:vscode:rwx

log_ok "Permissions guard applied to $REPO"