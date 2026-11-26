#!/usr/bin/env bash
# Runs setup.sh against stand-in agents in throwaway home folders, and checks what it left behind. Each case here
# is something the script once got wrong. Nothing outside the temporary folder is touched, and nothing is fetched.
#
#   bash tests/run.sh
# shellcheck disable=SC2034  # CODE, OUT and the like are read inside the quoted checks that ok() evaluates.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# SETUP_SCRIPT points the same cases at another copy of the script, to see that they catch what it gets wrong.
SETUP="${SETUP_SCRIPT:-$ROOT/setup.sh}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PASSED=0; FAILED=0; CASE=""

# A fresh home folder, and a PATH holding only the named stand-in agents and the system's own commands.
fresh() {
  CASE="$1"; shift
  export HOME="$WORK/$CASE/home" STUB_STATE="$WORK/$CASE/state"
  unset CODEX_HOME STUB_PLUGIN_FAILS STUB_CODEX_OLD ORVIND_SKILLS_URL
  export ORVIND_TOOLKIT_SOURCE="$ROOT"
  mkdir -p "$HOME" "$WORK/$CASE/bin"
  local agent; for agent in "$@"; do ln -s "$ROOT/tests/stubs/$agent" "$WORK/$CASE/bin/$agent"; done
  export PATH="$WORK/$CASE/bin:/usr/bin:/bin"
}
# setup.sh with no terminal behind it, as in CI or when an agent runs it. Prints its output; sets CODE.
setup() {
  OUT="$(python3 -c 'import subprocess, sys; sys.exit(subprocess.run(sys.argv[1:], stdin=subprocess.DEVNULL, start_new_session=True).returncode)' bash "$SETUP" "$@" 2>&1)"; CODE=$?
}
ok() { if eval "$2"; then PASSED=$((PASSED + 1)); else FAILED=$((FAILED + 1)); printf 'FAIL  %s: %s\n      %s\n' "$CASE" "$1" "$2"; printf '%s\n' "$OUT" | sed 's/^/      | /'; fi; }
mode() { python3 -c 'import os, stat, sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])' "$1"; }
blocks() { grep -c '^\[mcp_servers\.orvind\]' "$1" 2>/dev/null || true; }

# ── Codex ───────────────────────────────────────────────────────────────────────────────────────────────────────
fresh codex-new codex
setup --yes
ok "exits 0" '[ "$CODE" -eq 0 ]'
ok "adds the server once" '[ "$(blocks "$HOME/.codex/config.toml")" = 1 ]'
ok "installs both skills" '[ -f "$HOME/.codex/skills/orvind-playables/SKILL.md" ] && [ -f "$HOME/.codex/skills/orvind-playground/SKILL.md" ]'
setup --yes
ok "a second run adds nothing" '[ "$(blocks "$HOME/.codex/config.toml")" = 1 ]'
setup --remove
ok "remove exits 0" '[ "$CODE" -eq 0 ]'
ok "remove takes the server out" '[ "$(blocks "$HOME/.codex/config.toml")" = 0 ]'
ok "remove takes the skills out" '[ ! -e "$HOME/.codex/skills/orvind-playables" ] && [ ! -e "$HOME/.codex/skills/orvind-playground" ]'

fresh codex-old codex
export STUB_CODEX_OLD=1
mkdir -p "$HOME/.codex"; printf 'model = "x"\n\n[mcp_servers.other]\nurl = "https://example.com"\n' > "$HOME/.codex/config.toml"
cp "$HOME/.codex/config.toml" "$WORK/codex-old/before"
setup --yes
ok "reports failure" '[ "$CODE" -eq 1 ]'
ok "leaves the settings file exactly as it was" 'cmp -s "$HOME/.codex/config.toml" "$WORK/codex-old/before"'
setup --yes
ok "a second run still leaves it as it was" 'cmp -s "$HOME/.codex/config.toml" "$WORK/codex-old/before"'

fresh codex-old-no-file codex
export STUB_CODEX_OLD=1
setup --yes
ok "creates no settings file when the server cannot be added" '[ ! -e "$HOME/.codex/config.toml" ]'

fresh codex-skills-fail codex
setup --yes
cp "$HOME/.codex/skills/orvind-playground/SKILL.md" "$WORK/codex-skills-fail/before"
export ORVIND_TOOLKIT_SOURCE="orvind/agent-toolkit" ORVIND_SKILLS_URL="file://$WORK/nowhere"
setup --yes
ok "a failed skill download says so" 'printf "%s" "$OUT" | grep -q "could not be fetched"'
ok "a failed skill download keeps the skills that were there" 'cmp -s "$HOME/.codex/skills/orvind-playground/SKILL.md" "$WORK/codex-skills-fail/before"'

# ── Cursor ──────────────────────────────────────────────────────────────────────────────────────────────────────
fresh cursor-token
mkdir -p "$HOME/.cursor"; printf '{"mcpServers":{"other":{"url":"https://example.com","headers":{"Authorization":"Bearer secret"}}}}\n' > "$HOME/.cursor/mcp.json"; chmod 600 "$HOME/.cursor/mcp.json"
setup --yes
ok "exits 0" '[ "$CODE" -eq 0 ]'
ok "adds the server" 'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d[\"mcpServers\"][\"orvind\"][\"url\"]==\"https://mcp.orvind.com\" else 1)" "$HOME/.cursor/mcp.json"'
ok "keeps the other server and its token" 'grep -q "Bearer secret" "$HOME/.cursor/mcp.json"'
ok "keeps the file private (600)" '[ "$(mode "$HOME/.cursor/mcp.json")" = 600 ]'
ok "installs both skills" '[ -f "$HOME/.cursor/skills/orvind-playables/SKILL.md" ] && [ -f "$HOME/.cursor/skills/orvind-playground/SKILL.md" ]'
ok "leaves no temporary file" '[ "$(ls -A "$HOME/.cursor" | grep -c orvind-)" = 0 ]'
before="$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$HOME/.cursor/mcp.json")"
setup --yes
ok "a second run does not rewrite the file" '[ "$(python3 -c "import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)" "$HOME/.cursor/mcp.json")" = "$before" ]'
setup --remove
ok "remove takes only orvind out" '! grep -q orvind "$HOME/.cursor/mcp.json" && grep -q "Bearer secret" "$HOME/.cursor/mcp.json"'
ok "remove keeps the file private (600)" '[ "$(mode "$HOME/.cursor/mcp.json")" = 600 ]'
ok "remove takes the skills out" '[ ! -e "$HOME/.cursor/skills/orvind-playables" ]'

fresh cursor-new
mkdir -p "$HOME/.cursor"
setup --yes
ok "a new settings file is private (600)" '[ "$(mode "$HOME/.cursor/mcp.json")" = 600 ]'

fresh cursor-link
mkdir -p "$HOME/.cursor" "$HOME/dotfiles"; printf '{"mcpServers":{}}\n' > "$HOME/dotfiles/mcp.json"; ln -s "$HOME/dotfiles/mcp.json" "$HOME/.cursor/mcp.json"
setup --yes
ok "a linked settings file stays a link" '[ -L "$HOME/.cursor/mcp.json" ]'
ok "the file the link points to gets the server" 'grep -q "mcp.orvind.com" "$HOME/dotfiles/mcp.json"'

fresh cursor-broken
mkdir -p "$HOME/.cursor"; printf '{ not json' > "$HOME/.cursor/mcp.json"
setup --yes
ok "reports failure" '[ "$CODE" -eq 1 ]'
ok "leaves a file that is not JSON as it is" '[ "$(cat "$HOME/.cursor/mcp.json")" = "{ not json" ]'
setup --status
ok "status says the file is not valid JSON" 'printf "%s" "$OUT" | grep -q "not valid JSON"'

fresh cursor-unreadable
mkdir -p "$HOME/.cursor"; printf '{"mcpServers":{}}\n' > "$HOME/.cursor/mcp.json"; chmod 000 "$HOME/.cursor/mcp.json"
if [ "$(id -u)" -ne 0 ]; then
  setup --status
  ok "status says the file cannot be read" 'printf "%s" "$OUT" | grep -q "cannot be read"'
  ok "status prints no Python error" '! printf "%s" "$OUT" | grep -q Traceback'
fi
chmod 600 "$HOME/.cursor/mcp.json"

fresh cursor-with-codex codex
mkdir -p "$HOME/.cursor"
setup --yes
ok "with Codex's skills in place, Cursor gets no second copy" '[ ! -e "$HOME/.cursor/skills/orvind-playables" ] && printf "%s" "$OUT" | grep -q "from Codex"'

# ── Claude Code ─────────────────────────────────────────────────────────────────────────────────────────────────
fresh claude-plugin claude
setup --yes
ok "exits 0" '[ "$CODE" -eq 0 ]'
ok "installs the plugin" '[ -f "$STUB_STATE/plugin" ]'
ok "follows the published branch" '[ "$(cat "$STUB_STATE/marketplace")" = "$ROOT" ]'
setup --remove
ok "remove takes the plugin out" '[ ! -f "$STUB_STATE/plugin" ] && printf "%s" "$OUT" | grep -q "Orvind removed"'

fresh claude-branch claude
export ORVIND_TOOLKIT_SOURCE="orvind/agent-toolkit"
setup --yes --client claude-code
ok "the marketplace is added at the release branch" '[ "$(cat "$STUB_STATE/marketplace")" = "orvind/agent-toolkit@release" ]'

fresh claude-moves-branch claude
export ORVIND_TOOLKIT_SOURCE="orvind/agent-toolkit"
mkdir -p "$STUB_STATE"; echo "orvind/agent-toolkit" > "$STUB_STATE/marketplace"; touch "$STUB_STATE/plugin"
setup --yes
ok "an earlier setup on the default branch moves to the release branch" '[ "$(cat "$STUB_STATE/marketplace")" = "orvind/agent-toolkit@release" ]'
ok "the plugin is installed again after the move" '[ -f "$STUB_STATE/plugin" ] && [ "$CODE" -eq 0 ]'
echo marker > "$STUB_STATE/plugin"
setup --yes
ok "a setup already on the release branch is updated, not reinstalled" '[ "$(cat "$STUB_STATE/plugin")" = marker ]'

fresh claude-fallback claude
export STUB_PLUGIN_FAILS=1
setup --yes
ok "adds the server on its own when the plugin cannot be installed" 'grep -q "^orvind: https://mcp.orvind.com" "$STUB_STATE/servers"'
setup --yes
ok "a second run does not add it twice" '[ "$(grep -c "^orvind:" "$STUB_STATE/servers")" = 1 ]'
setup --status
ok "status says it is there without the skills" 'printf "%s" "$OUT" | grep -q "on its own"'
setup --remove
ok "remove takes that server out too" '! grep -q "^orvind:" "$STUB_STATE/servers"'
ok "remove exits 0" '[ "$CODE" -eq 0 ]'

fresh claude-own-server claude
mkdir -p "$STUB_STATE"; echo "mine: https://mcp.orvind.com (HTTP) - ok" > "$STUB_STATE/servers"
setup --remove
ok "remove leaves a server under the person's own name" 'grep -q "^mine:" "$STUB_STATE/servers"'
ok "remove says nothing was set up" 'printf "%s" "$OUT" | grep -q "was not set up"'

# ── Options ─────────────────────────────────────────────────────────────────────────────────────────────────────
fresh help-piped claude
OUT="$(bash -s -- --help < "$SETUP" 2>&1)"; CODE=$?
ok "--help through a pipe exits 0" '[ "$CODE" -eq 0 ]'
ok "--help through a pipe prints the options" 'printf "%s" "$OUT" | grep -q -- "--status" && printf "%s" "$OUT" | grep -q -- "--yes"'

fresh no-terminal claude codex
mkdir -p "$HOME/.cursor"
setup
ok "without a terminal and without --yes it exits 1" '[ "$CODE" -eq 1 ]'
ok "it says to add --yes" 'printf "%s" "$OUT" | grep -q -- "--yes"'
ok "it prints no /dev/tty error" '! printf "%s" "$OUT" | grep -q "/dev/tty"'
ok "it changes nothing" '[ ! -f "$STUB_STATE/plugin" ] && [ ! -e "$HOME/.codex" ] && [ ! -e "$HOME/.cursor/mcp.json" ]'
setup --status
ok "--status needs no terminal" '[ "$CODE" -eq 0 ]'

fresh missing-agent claude
setup --yes --client codex
ok "an agent asked for and not there is named" 'printf "%s" "$OUT" | grep -q "Codex was not found"'
ok "it does not say no agent was found" '! printf "%s" "$OUT" | grep -q "No supported agent"'
ok "it exits 1" '[ "$CODE" -eq 1 ]'
setup --yes --client codex --client claude-code
ok "the agents that are there are still set up" '[ -f "$STUB_STATE/plugin" ] && [ "$CODE" -eq 1 ]'

fresh no-agent
setup --yes
ok "with no agent it says so and exits 1" 'printf "%s" "$OUT" | grep -q "No supported agent" && [ "$CODE" -eq 1 ]'
setup --bogus
ok "an unknown option exits 2" '[ "$CODE" -eq 2 ]'

printf '%s passed, %s failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
