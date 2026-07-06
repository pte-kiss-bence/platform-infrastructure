#!/usr/bin/env sh
set -e

LOG_SCOPE=ssh-keys
. "$(dirname "$0")/log.sh"
log_enable_error_trap

# The host (WSL) ~/.ssh arrives as a readonly mount at ~/.ssh-localhost
# (devcontainer.json mounts). On a bind mount the file permissions mirror
# the host — with .ssh symlinked under /mnt/c that means 777, which ssh
# rejects for private keys. Hence a copy with 600, not direct use.
# Idempotent; refreshed on every postStart, so a key added on the host
# shows up inside after a reload.

SRC=/home/vscode/.ssh-localhost
DEST=/home/vscode/.ssh

if [ ! -d "$SRC" ] || [ -z "$(ls -A "$SRC" 2> /dev/null)" ]; then
  log_ok "No host .ssh mount ($SRC empty) — skipping"
  exit 0
fi

log_step "Copying host SSH keys: $SRC -> $DEST"
mkdir -p "$DEST"
chmod 700 "$DEST"
for f in "$SRC"/*; do
  [ -f "$f" ] || continue
  cp -f "$f" "$DEST/$(basename "$f")"
done
find "$DEST" -maxdepth 1 -type f -exec chmod 600 {} +
find "$DEST" -maxdepth 1 -type f -name '*.pub' -exec chmod 644 {} +

log_ok "Host SSH keys available in $DEST"
