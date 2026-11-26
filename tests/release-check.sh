#!/usr/bin/env bash
# Installs the toolkit with the real agent commands on this machine, in throwaway settings folders, and checks that
# what a person ends up with works: the plugin, its Orvind server and its skills. Run it on the folder before a
# release, and on the published branch after one. Nothing in your own settings is touched.
#
#   bash tests/release-check.sh              the folder this script is in
#   bash tests/release-check.sh release      the published branch on GitHub (or any branch or tag)
#
# It exists because 0.3.0 and 0.3.1 were published with an empty .mcp.json: the plugin installed, its version was
# right, and it had no server. Only looking at the installed result shows that.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="${1:-}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home" CLAUDE_CONFIG_DIR="$WORK/claude" CODEX_HOME="$WORK/codex"
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR" "$CODEX_HOME"
# Never inside the toolkit folder: an agent command run there reads, and can change, the folder's own .mcp.json.
cd "$WORK" || exit 1

if [ -n "$REF" ]; then
  SETUP="$WORK/setup.sh"; export ORVIND_TOOLKIT_REF="$REF"
  curl -fsSL "https://raw.githubusercontent.com/orvind/agent-toolkit/$REF/setup.sh" -o "$SETUP" || { echo "FAIL  could not fetch setup.sh from $REF"; exit 1; }
  echo "Checking the published toolkit at \"$REF\""
else
  SETUP="$ROOT/setup.sh"; export ORVIND_TOOLKIT_SOURCE="$ROOT"
  echo "Checking the toolkit in $ROOT"
fi

FAILED=0; CHECKED=0; code=0
ok() { CHECKED=$((CHECKED + 1)); if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; FAILED=$((FAILED + 1)); fi; }
before="$(cd "$ROOT" && git status --porcelain 2>/dev/null)"

if command -v claude >/dev/null 2>&1; then
  bash "$SETUP" --yes --client claude-code < /dev/null > "$WORK/claude.out" 2>&1; code=$?
  ok "Claude Code: the setup exits 0" '[ "$code" -eq 0 ]'
  plugins="$(claude plugin list 2>/dev/null)"; servers="$(claude mcp list 2>/dev/null)"
  ok "Claude Code: the plugin is installed" 'printf "%s" "$plugins" | grep -q "orvind@orvind"'
  ok "Claude Code: the plugin brings the Orvind server (it shows under /mcp)" 'printf "%s" "$servers" | grep -q "^plugin:orvind:orvind: https://mcp.orvind.com"'
  ok "Claude Code: the server answers and waits for sign-in" 'printf "%s" "$servers" | grep "^plugin:orvind:orvind:" | grep -qi "authentication"'
  ok "Claude Code: both skills are in the installed plugin" 'ls "$CLAUDE_CONFIG_DIR"/plugins/cache/orvind/orvind/*/skills/orvind-playables/SKILL.md "$CLAUDE_CONFIG_DIR"/plugins/cache/orvind/orvind/*/skills/orvind-playground/SKILL.md >/dev/null 2>&1'
  if [ -z "$REF" ]; then
    version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/.claude-plugin/plugin.json")"
    ok "Claude Code: the installed version is $version" 'printf "%s" "$plugins" | grep -A1 "orvind@orvind" | grep -q "$version"'
  fi
  bash "$SETUP" --remove --client claude-code > /dev/null 2>&1
  ok "Claude Code: --remove leaves nothing" '! claude plugin list 2>/dev/null | grep -q "orvind@orvind" && ! claude mcp list 2>/dev/null | grep -qi orvind'
else
  echo "skip  Claude Code is not installed here: THE PLUGIN WAS NOT CHECKED"; FAILED=$((FAILED + 1))
fi

if command -v codex >/dev/null 2>&1; then
  bash "$SETUP" --yes --client codex < /dev/null > "$WORK/codex.out" 2>&1; code=$?
  ok "Codex: the setup exits 0" '[ "$code" -eq 0 ]'
  ok "Codex: it reads the Orvind server" 'codex mcp get orvind 2>/dev/null | grep -q "https://mcp.orvind.com"'
  ok "Codex: the sign-in list is there, without openid" 'grep -q "^scopes = \[\"profile\", \"email\"\]$" "$CODEX_HOME/config.toml"'
  ok "Codex: both skills are installed" '[ -f "$CODEX_HOME/skills/orvind-playables/SKILL.md" ] && [ -f "$CODEX_HOME/skills/orvind-playground/SKILL.md" ]'
else
  echo "skip  Codex is not installed here"
fi

ok "the toolkit folder is exactly as it was (nothing here edited its files)" '[ "$(cd "$ROOT" && git status --porcelain 2>/dev/null)" = "$before" ]'

echo "$CHECKED checked, $FAILED failed"
[ "$FAILED" -eq 0 ]
