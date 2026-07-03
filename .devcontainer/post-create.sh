#!/usr/bin/env sh
set -e

LOG_SCOPE=post-create
. "$(dirname "$0")/log.sh"
log_enable_error_trap

# Install base CLI tooling. bash-completion gives tab-completion for git etc;
# git is usually present already but we pin it here so the container never
# depends on the base image shipping it.
log_step "Installing base CLI tooling (git, bash-completion, nano)"
sudo apt-get update
sudo apt-get install -y git bash-completion nano

# The Ubuntu base image ships the completion-loader block in /etc/bash.bashrc
# commented out, so interactive shells never source it. Append our own loader
# (idempotent: guarded by a grep so rebuilds don't duplicate the line).
log_step "Enabling bash-completion loader in /etc/bash.bashrc"
if ! grep -q 'devcontainer bash-completion' /etc/bash.bashrc; then
  printf '%s\n%s\n' \
    '# devcontainer bash-completion' \
    '[ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion' \
    | sudo tee -a /etc/bash.bashrc > /dev/null
fi

# Activate latest pnpm via corepack. corepack ships with Node 16+ and is the
# canonical way to manage package manager versions without a separate installer.
# --activate ensures the version becomes the active shim immediately.
log_step "Activating pnpm via corepack"
corepack enable
COREPACK_ENABLE_DOWNLOAD_PROMPT=0 corepack prepare pnpm@latest --activate

# pnpm setup writes the global bin path into shell rc files, but those aren't
# sourced in a non-interactive postCreateCommand script. Export the path
# explicitly so subsequent pnpm add -g calls work within this same session.
export PNPM_HOME="/home/vscode/.local/share/pnpm"
export PATH="$PNPM_HOME/bin:$PNPM_HOME:$PATH"

# The exports above only live for THIS script. Without persisting them, a normal
# terminal won't have the pnpm global bin on PATH, so the installed CLIs (ncu,
# skills, openspec) aren't found and `pnpm` global commands error with
# "global bin directory ... is not in PATH". Append a loader to /etc/bash.bashrc
# (system-wide, every user) — matching the bash-completion approach above rather
# than relying on `pnpm setup`. Grep-guarded so rebuilds don't duplicate it.
log_step "Adding pnpm global bin to PATH in /etc/bash.bashrc"
if ! grep -q 'devcontainer pnpm path' /etc/bash.bashrc; then
  printf '%s\n%s\n%s\n' \
    '# devcontainer pnpm path' \
    'export PNPM_HOME="/home/vscode/.local/share/pnpm"' \
    'export PATH="$PNPM_HOME/bin:$PATH"' \
    | sudo tee -a /etc/bash.bashrc > /dev/null
fi

# Install global CLI tooling shared across this template's projects. Kept here
# (not in the image) so the pinned Node feature provides pnpm first. pnpm add -g
# is idempotent, so rebuilds simply re-assert the same versions.
#
# --ignore-scripts is required: pnpm blocks dependency build/postinstall scripts
# by default and, under the TTY that postCreateCommand runs in, prompts
# interactively ("Choose which packages to build") — which hangs the container
# start forever. None of these packages need an install-time script (only
# @fission-ai/openspec ships a postinstall, and it merely prints a shell-
# completion tip), so skipping them is safe and keeps the install non-interactive.
log_step "Installing global CLI tooling (npm-check-updates, skills, OpenSpec)"
pnpm add -g --ignore-scripts \
  npm-check-updates \
  skills \
  @fission-ai/openspec

# Install project dependencies so a freshly created (or rebuilt) container has a populated
# node_modules. Idempotent, so rebuilds just re-assert the same install.
log_step "Installing project dependencies (pnpm install)"
pnpm install

# Fix ownership for Claude directory
log_step "Fixing ownership of /home/vscode/.claude-devcontainer"
sudo chown -R vscode:vscode /home/vscode/.claude-devcontainer || log_warn "chown skipped (dir absent?)"

# Default Claude Code to bypass-permissions mode INSIDE the container only. The
# repo runs in an isolated devcontainer, which is exactly the sandboxed setting
# where skipping per-action approval prompts (the --dangerously-skip-permissions
# workflow) is the recommended way to work. We write it into the container's
# CLAUDE_CONFIG_DIR user settings rather than the committed .claude/settings.json,
# so it stays strictly devcontainer-scoped: opening the repo on the host keeps
# normal prompting. Idempotent and merge-preserving (existing keys like model /
# effortLevel are kept) via a JSON read-modify-write in Node (always present).
log_step "Writing devcontainer-scoped Claude bypassPermissions setting"
CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-/home/vscode/.claude-devcontainer}/settings.json"
node -e '
  const fs = require("fs"), path = require("path"), p = process.argv[1];
  let s = {};
  try { s = JSON.parse(fs.readFileSync(p, "utf8")); } catch (e) {}
  s.permissions = { ...(s.permissions || {}), defaultMode: "bypassPermissions" };
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(s, null, 2) + "\n");
' "$CLAUDE_SETTINGS"

# Durable whole-repo permission guard: heal any root-owned paths and set default
# ACLs so files created later (incl. by root processes) stay vscode-writable.
# Persistent on ext4, so this survives restarts; idempotent across rebuilds.
log_step "Running workspace permission guard"
sh .devcontainer/fix-permissions.sh "$(pwd)"

# Mark the bind-mounted workspace as a safe directory. The repo lives on a host
# bind mount, so git's dubious-ownership check trips on every rebuild and blocks
# all git commands until cleared. Set it system-wide (/etc/gitconfig) so it
# covers EVERY user — including root, since some git operations run as root.
# The grep guard keeps it idempotent: --add would otherwise append a duplicate
# line on every rebuild.
log_step "Configuring git (safe.directory, identity, editor, GitHub auth)"
if ! git config --system --get-all safe.directory 2> /dev/null | grep -qxF "$(pwd)"; then
  sudo git config --system --add safe.directory "$(pwd)"
fi

# Persist git commit identity across container rebuilds. Values come from the
# git-ignored .devcontainer/.env (injected via runArgs --env-file), so each
# rebuild re-applies them. We set it system-wide (/etc/gitconfig) so it applies
# to EVERY user in the container - including root, since some git operations run
# as root. The PAT handles auth; git still needs an author identity.
if [ -n "$GIT_USER_NAME" ]; then
  sudo git config --system user.name "$GIT_USER_NAME"
else
  log_warn "GIT_USER_NAME unset in .env - commits will lack an author name"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
  sudo git config --system user.email "$GIT_USER_EMAIL"
else
  log_warn "GIT_USER_EMAIL unset in .env - commits will lack an author email"
fi

# Default to nano for git's interactive editor (commit messages, --amend,
# interactive rebase). The bare ubuntu base falls back to vim otherwise. Set
# system-wide (/etc/gitconfig) so every user gets it; idempotent on rebuild.
sudo git config --system core.editor "nano"

# Auto-create the upstream on first push of a new branch, so `git push` alone
# works instead of erroring with "has no upstream branch" and demanding
# `--set-upstream`. System-wide; setting a single-value key is idempotent.
sudo git config --system push.autoSetupRemote "true"

# Use the PAT for GitHub HTTPS auth so `git push`/`pull` work without prompting.
# The helper reads GITHUB_PERSONAL_ACCESS_TOKEN from the env (injected via
# --env-file) at call time, so the token is never written to disk and it works
# for any user. The empty reset first bypasses the helper VS Code injects, so
# ours wins for github.com.
if [ -n "$GITHUB_PERSONAL_ACCESS_TOKEN" ]; then
  sudo git config --system credential.https://github.com.helper ""
  sudo git config --system --add credential.https://github.com.helper '!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$GITHUB_PERSONAL_ACCESS_TOKEN"; }; f'
else
  log_warn "GITHUB_PERSONAL_ACCESS_TOKEN unset in .env - git push/pull will prompt"
fi

# Performance guard. WSL2 (native ext4) is the recommended host. When the workspace instead
# lives on a Windows drive it reaches the container over the 9p/drvfs protocol, where every
# file stat crosses the host boundary and file-heavy tooling (typed `ng lint`) runs minutes
# slow. Detect that slow path and steer the user to WSL — printed last so it stays visible.
log_ok "post-create complete"

WORKSPACE_FSTYPE="$(findmnt -n -o FSTYPE -T "$(pwd)" 2> /dev/null || true)"
if [ "$WORKSPACE_FSTYPE" = "9p" ] || [ "$WORKSPACE_FSTYPE" = "drvfs" ]; then
  printf '\n\033[33m========================================================================\n'
  printf '  PERFORMANCE: workspace is on a Windows drive (%s) — file I/O is slow.\n' "$WORKSPACE_FSTYPE"
  printf '  Recommended: move this repo onto the WSL2 native filesystem (ext4) and\n'
  printf '  reopen it via Remote-WSL, e.g. inside your WSL distro:\n'
  printf '      git clone <repo-url> ~/projects/%s\n' "$(basename "$(pwd)")"
  printf '      code ~/projects/%s   # then: Reopen in Container\n' "$(basename "$(pwd)")"
  printf '  Do NOT use /mnt/c or /mnt/d — those are still 9p/drvfs and just as slow.\n'
  printf '========================================================================\033[0m\n\n'
fi