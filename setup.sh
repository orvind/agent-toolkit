#!/usr/bin/env bash
# Sets up Orvind for the coding agents on this machine: Claude Code, Codex and Cursor.
#
#   curl -fsSL https://raw.githubusercontent.com/orvind/agent-toolkit/release/setup.sh | bash
#
# For each agent it finds, it adds the Orvind MCP server (https://mcp.orvind.com) and the Orvind skills. It needs no
# password and installs no program: it only calls each agent's own commands and writes that agent's own settings.
# Nothing connects to an Orvind account until you sign in from the agent afterwards. Run "setup.sh --help" for the
# options.
set -euo pipefail

usage() {
  cat <<'HELP'
Sets up Orvind for the coding agents on this machine: Claude Code, Codex and Cursor.

  curl -fsSL https://raw.githubusercontent.com/orvind/agent-toolkit/release/setup.sh | bash

For each agent it finds, it adds the Orvind MCP server (https://mcp.orvind.com) and the Orvind skills. It needs no
password and installs no program. Nothing connects to an Orvind account until you sign in from the agent afterwards.

  --status           Show what is set up and change nothing.
  --client <name>    Only this agent: claude-code, codex or cursor. Repeat for more than one.
  --yes              Do not ask before setting up each agent. Needed when there is no terminal to ask on.
  --remove           Take Orvind out of the agents again.
  --help             Show this.

Through the pipe, options go after "bash -s --":
  curl -fsSL https://raw.githubusercontent.com/orvind/agent-toolkit/release/setup.sh | bash -s -- --status
HELP
}

SERVER_URL="${ORVIND_MCP_URL:-https://mcp.orvind.com}"
# The published toolkit is the "release" branch of the GitHub repo: "main" is where it is worked on. To test a copy
# before it is published, ORVIND_TOOLKIT_SOURCE may be a local folder.
REF="${ORVIND_TOOLKIT_REF:-release}"
TOOLKIT="${ORVIND_TOOLKIT_SOURCE:-orvind/agent-toolkit}"
SKILLS_URL="${ORVIND_SKILLS_URL:-https://raw.githubusercontent.com/orvind/agent-toolkit/$REF/skills}"
SKILLS="orvind-playables orvind-playground"
if [ -d "$TOOLKIT" ]; then MARKETPLACE="$TOOLKIT"; else MARKETPLACE="$TOOLKIT@$REF"; fi

MODE=setup; YES=0; CLIENTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --status) MODE=status ;;
    --remove) MODE=remove ;;
    --yes|-y) YES=1 ;;
    --client) shift; [ $# -gt 0 ] || { echo "--client needs a name: claude-code, codex or cursor." >&2; exit 2; }; CLIENTS+=("$1") ;;
    --client=*) CLIENTS+=("${1#--client=}") ;;
    -h|--help) usage; exit 0 ;;
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
# Whether a person can be asked: the terminal itself, so it also works when this script arrives through a pipe.
# /dev/tty exists even when there is no terminal behind it, so it is opened, not only looked at.
can_ask() { { : > /dev/tty; } 2>/dev/null; }
confirm() {
  [ "$YES" -eq 1 ] && return 0
  local answer; printf '%s [Y/n] ' "$1" > /dev/tty; read -r answer < /dev/tty || return 1
  case "$answer" in n|N|no|No|NO) return 1 ;; *) return 0 ;; esac
}

# The skill files: copied from a local toolkit folder, or fetched from the published one. All of them are fetched
# before any is put in place, so a failed download leaves the skills that were there as they were.
skills_into() {
  local skill stage
  stage="$(mktemp -d)" || return 1
  for skill in $SKILLS; do
    if [ -f "$TOOLKIT/skills/$skill/SKILL.md" ]; then cp "$TOOLKIT/skills/$skill/SKILL.md" "$stage/$skill.md" || { rm -rf "$stage"; return 1; }
    else curl -fsSL "$SKILLS_URL/$skill/SKILL.md" -o "$stage/$skill.md" 2>/dev/null || { rm -rf "$stage"; return 1; }; fi
    # A skill file starts with its name and description; anything else is an error page or a cut-off download.
    [ "$(head -n 1 "$stage/$skill.md" 2>/dev/null)" = "---" ] || { rm -rf "$stage"; return 1; }
  done
  for skill in $SKILLS; do
    { mkdir -p "$1/$skill" && cp "$stage/$skill.md" "$1/$skill/SKILL.md.orvind-tmp" && mv -f "$1/$skill/SKILL.md.orvind-tmp" "$1/$skill/SKILL.md"; } || { rm -rf "$stage"; return 1; }
  done
  rm -rf "$stage"
}
skills_in() { local skill; for skill in $SKILLS; do [ -f "$1/$skill/SKILL.md" ] || return 1; done; }
skills_out() { local skill; for skill in $SKILLS; do rm -rf "${1:?}/$skill"; done; }

# ── Claude Code ─────────────────────────────────────────────────────────────────────────────────────────────────
claude_plugin() { claude plugin list 2>/dev/null | grep -q 'orvind@orvind'; }
# The Orvind server on its own, under the name this script gives it when the plugin cannot be installed.
# Listed from the home folder, so a project's own servers (a folder with an .mcp.json) are not taken for the person's.
claude_servers() { (cd "$HOME" 2>/dev/null && claude mcp list 2>/dev/null) || true; }
claude_server() { claude_servers | grep -F "$SERVER_URL" | grep -q '^orvind:'; }
# An Orvind server outside the plugin, by address: with the plugin too, the agent would see every tool twice.
claude_manual() { claude_servers | grep -F "$SERVER_URL" | grep -v '^plugin:' | sed 's/:.*//' | head -1 || true; }
# The orvind marketplace as Claude Code has it, and the branch it follows (nothing when it follows the default one).
claude_market() { claude plugin marketplace list --json 2>/dev/null | tr -d ' \n' | grep -o '"name":"orvind"[^}]*' || true; }
claude_ref() { claude_market | sed -n 's/.*"ref":"\([^"]*\)".*/\1/p'; }
claude_status() {
  local manual; manual="$(claude_manual || true)"
  if claude_plugin; then say "  Claude Code: Orvind plugin installed."
  elif [ -n "$manual" ]; then say "  Claude Code: Orvind server added on its own as \"$manual\", without the plugin's skills."
  else say "  Claude Code: not set up."; fi
}
claude_setup() {
  # An earlier setup may follow another branch than the published one. Claude Code keeps the branch a marketplace
  # was added with, so it is taken out and added again; that takes the plugin with it, which is installed below.
  if [ ! -d "$TOOLKIT" ] && [ -n "$(claude_market)" ] && [ "$(claude_ref)" != "$REF" ]; then
    claude plugin marketplace remove orvind >/dev/null 2>&1 || true
  fi
  claude plugin marketplace add "$MARKETPLACE" >/dev/null 2>&1 || true
  if claude_plugin; then say "  Claude Code: already installed. Updating."; claude plugin marketplace update orvind >/dev/null 2>&1 || true; claude plugin update orvind@orvind >/dev/null 2>&1 || true
  elif claude plugin install orvind@orvind >/dev/null 2>&1; then say "  Claude Code: Orvind plugin installed."
  elif claude_server || claude mcp add --scope user --transport http orvind "$SERVER_URL" >/dev/null 2>&1; then say "  Claude Code: the plugin could not be installed, so the Orvind server was added on its own (no skills)."
  else say "  Claude Code: could not be set up. Add it by hand: claude mcp add --scope user --transport http orvind $SERVER_URL"; return 1; fi
  local manual; manual="$(claude_manual || true)"
  if claude_plugin && [ -n "$manual" ]; then say "    You also have the Orvind server added on its own as \"$manual\". Remove it so the agent does not see every tool twice: claude mcp remove $manual"; fi
  say "    Next: start claude, run /mcp, choose orvind and sign in."
}
claude_remove() {
  local was=0
  if claude_plugin; then was=1; claude plugin uninstall orvind@orvind >/dev/null 2>&1 || true; fi
  claude plugin marketplace remove orvind >/dev/null 2>&1 || true
  # The server this script adds on its own when the plugin cannot be installed. One under another name is the
  # person's own and is left alone.
  # Only the person's own (user) server, and from the home folder: without a scope, run inside a project, the
  # command would take "orvind" out of that project's .mcp.json instead.
  if claude_server; then was=1; (cd "$HOME" 2>/dev/null && claude mcp remove orvind --scope user >/dev/null 2>&1) || true; fi
  if claude_plugin; then say "  Claude Code: the plugin could not be removed. Remove it by hand: claude plugin uninstall orvind@orvind"; return 1; fi
  if claude_server; then say "  Claude Code: the Orvind server could not be removed. Remove it by hand: claude mcp remove orvind --scope user"; return 1; fi
  if [ "$was" -eq 1 ]; then say "  Claude Code: Orvind removed."; else say "  Claude Code: Orvind was not set up."; fi
}

# ── Codex ───────────────────────────────────────────────────────────────────────────────────────────────────────
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_FILE="$CODEX_DIR/config.toml"
CODEX_SKILLS="$CODEX_DIR/skills"
codex_has() { codex mcp get orvind >/dev/null 2>&1; }
# The server as written in Codex's settings file, whether or not this Codex can read it.
codex_block() { grep -q '^[[:space:]]*\[mcp_servers\.orvind\]' "$CODEX_FILE" 2>/dev/null; }
# What Codex asks for when it signs in. Left to itself it asks for everything Orvind's sign-in offers, an identity
# token (openid) among them, and the sign-in then fails; it takes the list from its own settings only.
CODEX_SCOPES='scopes = ["profile", "email"]'
# Whether the server in Codex's settings carries that list: one added by an earlier version of this script does not.
codex_scoped() {
  awk -v want="$CODEX_SCOPES" '
    /^[[:space:]]*\[/ { inside = ($0 ~ /^[[:space:]]*\[mcp_servers\.orvind\][[:space:]]*$/) }
    inside && index($0, want) { found = 1 }
    END { exit found ? 0 : 1 }' "$CODEX_FILE" 2>/dev/null
}
codex_status() {
  if codex_has && ! codex_scoped; then say "  Codex: Orvind server added by an earlier setup, which cannot sign in. Run the setup again."
  elif codex_has; then say "  Codex: Orvind server added$(skills_in "$CODEX_SKILLS" && echo ', skills installed' || echo ', skills missing')."
  elif codex_block; then say "  Codex: $CODEX_FILE has an orvind server, but this Codex does not read it. Update Codex."
  else say "  Codex: not set up."; fi
}
codex_setup() {
  # A server added without the sign-in list cannot be signed in to, so it is taken out and added again below.
  if codex_has && ! codex_scoped; then codex mcp remove orvind >/dev/null 2>&1 || true; fi
  if ! codex_has; then
    if codex_block; then
      say "  Codex: $CODEX_FILE already has an orvind server, but this Codex does not read it. Update Codex, then run this again."
      return 1
    fi
    # Written to Codex's settings file directly: "codex mcp add" would start the browser sign-in and wait for it.
    # If this Codex does not take it, the file is put back exactly as it was.
    local before="" existed=0
    mkdir -p "$CODEX_DIR"
    if [ -e "$CODEX_FILE" ]; then
      existed=1
      before="$(mktemp)" || return 1
      cp "$CODEX_FILE" "$before" 2>/dev/null || { rm -f "$before"; say "  Codex: $CODEX_FILE could not be read, so it was left as it is."; return 1; }
    fi
    if ! printf '\n[mcp_servers.orvind]\nurl = "%s"\n%s\n' "$SERVER_URL" "$CODEX_SCOPES" >> "$CODEX_FILE"; then
      [ -z "$before" ] || rm -f "$before"
      say "  Codex: $CODEX_FILE could not be written, so it was left as it is."
      return 1
    fi
    if ! codex_has; then
      if [ "$existed" -eq 1 ]; then cat "$before" > "$CODEX_FILE"; rm -f "$before"; else rm -f "$CODEX_FILE"; fi
      say "  Codex: could not add the server, and its settings were left as they were. Update Codex, then add it by hand: codex mcp add orvind --url $SERVER_URL, and sign in with: codex mcp login orvind --scopes profile,email"
      return 1
    fi
    [ -z "$before" ] || rm -f "$before"
  fi
  if skills_into "$CODEX_SKILLS"; then say "  Codex: Orvind server and skills installed."; else say "  Codex: Orvind server added. The skills could not be fetched; run this again later."; fi
  say "    Next: sign in with: codex mcp login orvind"
}
codex_remove() {
  codex mcp remove orvind >/dev/null 2>&1 || true
  skills_out "$CODEX_SKILLS"
  if codex_block; then say "  Codex: the skills were removed, but the server could not be. Delete the [mcp_servers.orvind] section from $CODEX_FILE."; return 1; fi
  say "  Codex: Orvind removed."
}

# ── Cursor ──────────────────────────────────────────────────────────────────────────────────────────────────────
CURSOR_FILE="$HOME/.cursor/mcp.json"
CURSOR_SKILLS="$HOME/.cursor/skills"
# Cursor keeps its servers in one JSON file, which may hold other servers' tokens and may be a link into a dotfiles
# folder. Only the "orvind" entry is read or written; the file keeps its permissions and stays a link; and it is
# not written at all when nothing would change. Exit: 0 done or present, 1 absent, 3 not JSON, 4 cannot be read
# or written.
cursor_json() {
  python3 - "$CURSOR_FILE" "$1" "$SERVER_URL" <<'PY'
import json, os, stat, sys, tempfile
path, action, url = sys.argv[1:4]
real = os.path.realpath(path)
existed = os.path.exists(real)
try:
    with open(real) as handle: data = json.load(handle)
except FileNotFoundError: data = {}
except ValueError: sys.exit(3)
except OSError: sys.exit(4)
if not isinstance(data, dict): sys.exit(3)
servers = data.get("mcpServers") if isinstance(data.get("mcpServers"), dict) else {}
present = isinstance(servers.get("orvind"), dict) and servers["orvind"].get("url") == url
if action == "has": sys.exit(0 if present else 1)
if action == "add":
    if present: sys.exit(0)
    servers["orvind"] = {"url": url}
if action == "remove":
    if "orvind" not in servers: sys.exit(0)
    servers.pop("orvind")
data["mcpServers"] = servers
try:
    folder = os.path.dirname(real)
    os.makedirs(folder, exist_ok=True)
    mode = stat.S_IMODE(os.stat(real).st_mode) if existed else 0o600
    handle, temporary = tempfile.mkstemp(dir=folder, prefix=".mcp.json.orvind-")
    try:
        with os.fdopen(handle, "w") as out: json.dump(data, out, indent=2); out.write("\n")
        os.chmod(temporary, mode)
        os.replace(temporary, real)
    except BaseException:
        if os.path.exists(temporary): os.unlink(temporary)
        raise
except OSError: sys.exit(4)
PY
}
cursor_by_hand() { say "  Cursor: add it by hand. In $CURSOR_FILE, under \"mcpServers\", add: \"orvind\": { \"url\": \"$SERVER_URL\" }"; }
# Cursor also reads the skills in Codex's folder, so with those in place a second copy would show every skill twice.
cursor_skills() { skills_in "$CURSOR_SKILLS" || skills_in "$CODEX_SKILLS"; }
cursor_status() {
  has python3 || { say "  Cursor: cannot be checked without python3."; return 0; }
  local code=0; cursor_json has || code=$?
  case "$code" in
    0) say "  Cursor: Orvind server added$(cursor_skills && echo ', skills installed' || echo ', skills missing')." ;;
    1) say "  Cursor: not set up." ;;
    3) say "  Cursor: $CURSOR_FILE is not valid JSON, so it cannot be checked." ;;
    *) say "  Cursor: $CURSOR_FILE cannot be read." ;;
  esac
}
cursor_setup() {
  has python3 || { cursor_by_hand; return 1; }
  local code=0; cursor_json add || code=$?
  case "$code" in
    0) ;;
    3) say "  Cursor: $CURSOR_FILE is not valid JSON, so it was left as it is."; cursor_by_hand; return 1 ;;
    *) say "  Cursor: $CURSOR_FILE could not be read or written, so it was left as it is."; cursor_by_hand; return 1 ;;
  esac
  if skills_in "$CODEX_SKILLS" && ! skills_in "$CURSOR_SKILLS"; then say "  Cursor: Orvind server added. It reads the skills from Codex's folder."
  elif skills_into "$CURSOR_SKILLS"; then say "  Cursor: Orvind server and skills installed."
  else say "  Cursor: Orvind server added. The skills could not be fetched; run this again later."; fi
  say "    Next: open Cursor's settings, MCP, and sign in on orvind."
}
cursor_remove() {
  skills_out "$CURSOR_SKILLS"
  if has python3 && cursor_json remove; then say "  Cursor: Orvind removed."; else say "  Cursor: the skills were removed. Remove \"orvind\" from $CURSOR_FILE by hand."; return 1; fi
}

# ── Run ─────────────────────────────────────────────────────────────────────────────────────────────────────────
label() { case "$1" in claude-code) echo "Claude Code" ;; codex) echo "Codex" ;; cursor) echo "Cursor" ;; esac; }
run() { case "$1" in claude-code) "claude_$2" ;; codex) "codex_$2" ;; cursor) "cursor_$2" ;; esac; }
here() {
  case "$1" in
    claude-code) has claude ;;
    codex) has codex ;;
    cursor) [ -d "$HOME/.cursor" ] || has cursor ;;
  esac
}

FOUND=(); FAILED=0
for client in claude-code codex cursor; do
  wanted "$client" || continue
  if here "$client"; then FOUND+=("$client")
  # An agent asked for by name and not there is said by name; without --client, only what is there is listed.
  elif [ ${#CLIENTS[@]} -gt 0 ]; then say "$(label "$client") was not found on this machine."; FAILED=1; fi
done

if [ ${#FOUND[@]} -eq 0 ]; then
  [ ${#CLIENTS[@]} -gt 0 ] || say "No supported agent was found on this machine (Claude Code, Codex or Cursor)."
  say "In any other agent, add an MCP server with this address and sign in: $SERVER_URL"
  exit 1
fi

case "$MODE" in
  status) say "Orvind on this machine:"; for client in "${FOUND[@]}"; do run "$client" status; done; exit 0 ;;
  remove) say "Removing Orvind:"; for client in "${FOUND[@]}"; do run "$client" remove || FAILED=1; done ;;
  setup)
    if [ "$YES" -ne 1 ] && ! can_ask; then
      say "There is no terminal to ask on, so nothing was changed. To set up without being asked, add --yes:"
      say "  curl -fsSL https://raw.githubusercontent.com/orvind/agent-toolkit/release/setup.sh | bash -s -- --yes"
      exit 1
    fi
    say "Setting up Orvind ($SERVER_URL):"
    for client in "${FOUND[@]}"; do
      if confirm "Set up $(label "$client")?"; then run "$client" setup || FAILED=1; else say "  $(label "$client"): skipped."; fi
    done
    say ""
    say "Then try: \"List my Orvind campaigns.\""
    ;;
esac
exit "$FAILED"
