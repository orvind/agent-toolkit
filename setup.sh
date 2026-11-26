#!/usr/bin/env bash
# Sets up Orvind for the coding agents on this machine: Claude Code, Codex and Cursor.
#
#   curl -fsSL https://raw.githubusercontent.com/orvind/agent-toolkit/main/setup.sh | bash
#
# For each agent it finds, it adds the Orvind MCP server (https://mcp.orvind.com) and, where the agent supports
# them, the Orvind plugin and its skills. It needs no password and installs no program: it only calls
# each agent's own commands and writes that agent's own settings. Nothing connects to an Orvind account until
# you sign in from the agent afterwards.
#
#   --status                 Show what is set up and change nothing.
#   --client <name>          Only this agent: claude-code, codex or cursor. Repeat for more than one.
#   --yes                    Do not ask before setting up each agent.
#   --remove                 Take Orvind out of the agents again.
set -euo pipefail

SERVER_URL="${ORVIND_MCP_URL:-https://mcp.orvind.com}"
# Where the plugin lives: a GitHub repo, or a local folder when testing a copy before it is published.
TOOLKIT="${ORVIND_TOOLKIT_SOURCE:-orvind/agent-toolkit}"
SKILLS_URL="${ORVIND_SKILLS_URL:-https://raw.githubusercontent.com/orvind/agent-toolkit/main/skills}"
SKILLS="orvind-playables orvind-playground"

MODE=setup; YES=0; CLIENTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --status) MODE=status ;;
    --remove) MODE=remove ;;
    --yes|-y) YES=1 ;;
    --client) shift; [ $# -gt 0 ] || { echo "--client needs a name: claude-code, codex or cursor." >&2; exit 2; }; CLIENTS+=("$1") ;;
    --client=*) CLIENTS+=("${1#--client=}") ;;
    -h|--help) sed -n '2,15p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
for client in ${CLIENTS[@]+"${CLIENTS[@]}"}; do
  case "$client" in claude-code|codex|cursor) ;; *) echo "Unknown agent: $client. Use claude-code, codex or cursor." >&2; exit 2 ;; esac
done

say() { printf '%s\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }
wanted() { [ ${#CLIENTS[@]} -eq 0 ] && return 0; local c; for c in "${CLIENTS[@]}"; do [ "$c" = "$1" ] && return 0; done; return 1; }
# Asked on the terminal itself, so it also works when this script arrives through a pipe.
confirm() {
  [ "$YES" -eq 1 ] && return 0
  [ -r /dev/tty ] && [ -w /dev/tty ] || return 0
  local answer; printf '%s [Y/n] ' "$1" > /dev/tty; read -r answer < /dev/tty || return 0
  case "$answer" in n|N|no|No|NO) return 1 ;; *) return 0 ;; esac
}
# The skill files: copied from a local toolkit folder, or fetched from the published one.
skills_into() {
  local skill dir
  for skill in $SKILLS; do
    dir="$1/$skill"; mkdir -p "$dir"
    if [ -f "$TOOLKIT/skills/$skill/SKILL.md" ]; then cp "$TOOLKIT/skills/$skill/SKILL.md" "$dir/SKILL.md"
    else curl -fsSL "$SKILLS_URL/$skill/SKILL.md" -o "$dir/SKILL.md" || return 1; fi
  done
}
skills_in() { local skill; for skill in $SKILLS; do [ -f "$1/$skill/SKILL.md" ] || return 1; done; }
skills_out() { local skill; for skill in $SKILLS; do rm -rf "${1:?}/$skill"; done; }

# ── Claude Code ─────────────────────────────────────────────────────────────────────────────────────────────────
claude_plugin() { claude plugin list 2>/dev/null | grep -q 'orvind@orvind'; }
# An Orvind server added by hand, by address: with the plugin too, the agent would see every tool twice.
claude_manual() { claude mcp list 2>/dev/null | grep -F "$SERVER_URL" | grep -v '^plugin:' | sed 's/:.*//' | head -1 || true; }
claude_status() {
  if claude_plugin; then say "  Claude Code: Orvind plugin installed."
  elif [ -n "$(claude_manual)" ]; then say "  Claude Code: Orvind server added by hand as \"$(claude_manual)\", without the plugin's skills."
  else say "  Claude Code: not set up."; fi
}
claude_setup() {
  if claude_plugin; then say "  Claude Code: already installed. Updating."; claude plugin marketplace update orvind >/dev/null 2>&1 || true; claude plugin update orvind@orvind >/dev/null 2>&1 || true
  else
    claude plugin marketplace add "$TOOLKIT" >/dev/null 2>&1 || true
    if claude plugin install orvind@orvind >/dev/null 2>&1; then say "  Claude Code: Orvind plugin installed."
    elif claude mcp add --scope user --transport http orvind "$SERVER_URL" >/dev/null 2>&1; then say "  Claude Code: the plugin could not be installed, so the Orvind server was added on its own (no skills)."
    else say "  Claude Code: could not be set up. Add it by hand: claude mcp add --scope user --transport http orvind $SERVER_URL"; return 1; fi
  fi
  local manual; manual="$(claude_manual || true)"
  if claude_plugin && [ -n "$manual" ]; then say "    You also have the Orvind server added by hand as \"$manual\". Remove it so the agent does not see every tool twice: claude mcp remove $manual"; fi
  say "    Next: start claude, run /mcp, choose orvind and sign in."
}
claude_remove() {
  claude plugin uninstall orvind@orvind >/dev/null 2>&1 || true
  claude plugin marketplace remove orvind >/dev/null 2>&1 || true
  say "  Claude Code: Orvind plugin removed."
}

# ── Codex ───────────────────────────────────────────────────────────────────────────────────────────────────────
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_SKILLS="$CODEX_DIR/skills"
codex_has() { codex mcp get orvind >/dev/null 2>&1; }
codex_status() { if codex_has; then say "  Codex: Orvind server added$(skills_in "$CODEX_SKILLS" && echo ', skills installed' || echo ', skills missing')."; else say "  Codex: not set up."; fi; }
codex_setup() {
  # Written to Codex's settings file directly: "codex mcp add" would start the browser sign-in and wait for it.
  if ! codex_has; then
    mkdir -p "$CODEX_DIR"
    printf '\n[mcp_servers.orvind]\nurl = "%s"\n' "$SERVER_URL" >> "$CODEX_DIR/config.toml"
    codex_has || { say "  Codex: could not add the server. Update Codex, then add it by hand: codex mcp add orvind --url $SERVER_URL"; return 1; }
  fi
  if skills_into "$CODEX_SKILLS" 2>/dev/null; then say "  Codex: Orvind server and skills installed."; else say "  Codex: Orvind server added. The skills could not be fetched."; fi
  say "    Next: sign in with: codex mcp login orvind"
}
codex_remove() { codex mcp remove orvind >/dev/null 2>&1 || true; skills_out "$CODEX_SKILLS"; say "  Codex: Orvind removed."; }

# ── Cursor ──────────────────────────────────────────────────────────────────────────────────────────────────────
CURSOR_FILE="$HOME/.cursor/mcp.json"
# Cursor keeps its servers in one JSON file; only the "orvind" entry in it is read or written.
cursor_json() {
  python3 - "$CURSOR_FILE" "$1" "$SERVER_URL" <<'PY'
import json, os, sys
path, action, url = sys.argv[1:4]
try:
    with open(path) as handle: data = json.load(handle)
except FileNotFoundError: data = {}
except ValueError: sys.exit(3)
if not isinstance(data, dict): sys.exit(3)
servers = data.get("mcpServers") if isinstance(data.get("mcpServers"), dict) else {}
if action == "has": sys.exit(0 if isinstance(servers.get("orvind"), dict) and servers["orvind"].get("url") == url else 1)
if action == "add": servers["orvind"] = {"url": url}
if action == "remove": servers.pop("orvind", None)
data["mcpServers"] = servers
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path + ".orvind-tmp", "w") as handle: json.dump(data, handle, indent=2); handle.write("\n")
os.replace(path + ".orvind-tmp", path)
PY
}
cursor_status() { if has python3 && cursor_json has; then say "  Cursor: Orvind server added."; else say "  Cursor: not set up."; fi; }
cursor_by_hand() { say "  Cursor: add it by hand. In $CURSOR_FILE, under \"mcpServers\", add: \"orvind\": { \"url\": \"$SERVER_URL\" }"; }
cursor_setup() {
  has python3 || { cursor_by_hand; return 1; }
  if cursor_json add; then say "  Cursor: Orvind server added."; say "    Next: open Cursor's settings, MCP, and sign in on orvind."
  else say "  Cursor: $CURSOR_FILE could not be read as JSON, so it was left as it is."; cursor_by_hand; return 1; fi
}
cursor_remove() { has python3 && cursor_json remove && say "  Cursor: Orvind removed." || say "  Cursor: remove \"orvind\" from $CURSOR_FILE by hand."; }

# ── Run ─────────────────────────────────────────────────────────────────────────────────────────────────────────
FOUND=()
has claude && wanted claude-code && FOUND+=(claude-code)
has codex && wanted codex && FOUND+=(codex)
{ [ -d "$HOME/.cursor" ] || has cursor; } && wanted cursor && FOUND+=(cursor)

if [ ${#FOUND[@]} -eq 0 ]; then
  say "No supported agent was found on this machine (Claude Code, Codex or Cursor)."
  say "In any other agent, add an MCP server with this address and sign in: $SERVER_URL"
  exit 1
fi

label() { case "$1" in claude-code) echo "Claude Code" ;; codex) echo "Codex" ;; cursor) echo "Cursor" ;; esac; }
run() { case "$1" in claude-code) "claude_$2" ;; codex) "codex_$2" ;; cursor) "cursor_$2" ;; esac; }

FAILED=0
case "$MODE" in
  status) say "Orvind on this machine:"; for client in "${FOUND[@]}"; do run "$client" status; done ;;
  remove) say "Removing Orvind:"; for client in "${FOUND[@]}"; do run "$client" remove; done ;;
  setup)
    say "Setting up Orvind ($SERVER_URL):"
    for client in "${FOUND[@]}"; do
      if confirm "Set up $(label "$client")?"; then run "$client" setup || FAILED=1; else say "  $(label "$client"): skipped."; fi
    done
    say ""
    say "Then try: \"List my Orvind campaigns.\""
    ;;
esac
exit "$FAILED"
