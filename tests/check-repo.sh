#!/usr/bin/env bash
# Checks that the parts of the toolkit that must agree with each other do.
#
#   bash tests/check-repo.sh
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json, pathlib, re, sys
problems = []

# Every manifest is valid JSON, and the two plugin manifests carry the same version.
manifests = [".claude-plugin/plugin.json", ".claude-plugin/marketplace.json", ".cursor-plugin/plugin.json", ".cursor-plugin/marketplace.json", ".mcp.json"]
loaded = {}
for name in manifests:
    try: loaded[name] = json.loads(pathlib.Path(name).read_text())
    except (OSError, ValueError) as error: problems.append(f"{name}: {error}")
# The plugin's own server: without it the plugin installs with its skills and no Orvind tools.
server = loaded.get(".mcp.json", {}).get("mcpServers", {}).get("orvind")
if server != {"type": "http", "url": "https://mcp.orvind.com"}:
    problems.append(f".mcp.json must define the orvind server at https://mcp.orvind.com, but has: {server}")
versions = {name: loaded[name].get("version") for name in (".claude-plugin/plugin.json", ".cursor-plugin/plugin.json") if name in loaded}
if len(set(versions.values())) != 1 or not all(re.fullmatch(r"\d+\.\d+\.\d+", str(v)) for v in versions.values()):
    problems.append(f"the plugin versions differ or are not x.y.z: {versions}")

# Each skill names itself after its folder and has a description; setup.sh installs exactly the skills there are.
skills = sorted(path.parent.name for path in pathlib.Path("skills").glob("*/SKILL.md"))
signin = {}
for skill in skills:
    text = pathlib.Path("skills", skill, "SKILL.md").read_text()
    front = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not front: problems.append(f"skills/{skill}: no frontmatter"); continue
    name = re.search(r"^name:\s*(\S+)\s*$", front.group(1), re.M)
    if not name or name.group(1) != skill: problems.append(f"skills/{skill}: name must be {skill}")
    if not re.search(r"^description:", front.group(1), re.M): problems.append(f"skills/{skill}: no description")
    section = re.search(r"^## Before anything else\n(.*?)(?=^## )", text, re.S | re.M)
    if not section: problems.append(f"skills/{skill}: no 'Before anything else' section")
    else: signin[skill] = section.group(1).strip()
# The sign-in steps are repeated in every skill, because each skill is loaded on its own: they must not drift.
if len(set(signin.values())) > 1: problems.append("the 'Before anything else' section differs between skills: " + ", ".join(signin))
listed = re.search(r'^SKILLS="([^"]*)"', pathlib.Path("setup.sh").read_text(), re.M)
if not listed or sorted(listed.group(1).split()) != skills:
    problems.append(f"setup.sh installs {listed.group(1) if listed else None}, but skills/ has {skills}")

for problem in problems: print("FAIL ", problem)
print(f"{len(problems)} problem(s)")
sys.exit(1 if problems else 0)
PY
