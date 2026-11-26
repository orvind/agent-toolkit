# Orvind Agent Toolkit

Orvind's plugin for AI coding agents. It connects your agent to [Orvind](https://orvind.com) so you can work in the Playground from it: browse your campaigns, versions and playables, ask about a game, plan and make changes, play the result and save it as a version.

## What's included

| Part | What it is |
| --- | --- |
| MCP server `orvind` | `https://mcp.orvind.com`. Signs you in with your Orvind account; the agent then works as you, in the teams you belong to. |
| Skill `orvind-playground` | The order of work and the rules for the Playground: campaign, then version, then playable; showing a plan before starting a change; previews; saving. |

Nothing connects until you sign in from your agent. Starting a change spends your team's credits, as it does in the app, and the agent asks you first.

## Set up

One command finds Claude Code, Codex and Cursor on your machine and sets up each one:

```bash
curl -fsSL https://raw.githubusercontent.com/orvind/agent-toolkit/main/setup.sh | bash
```

It installs no program and needs no password. It calls each agent's own commands and writes that agent's own settings.

| Option | What it does |
| --- | --- |
| `--status` | Shows what is set up and changes nothing. |
| `--client claude-code` | Sets up only that agent (`claude-code`, `codex` or `cursor`). Repeat for more than one. |
| `--yes` | Does not ask before each agent. |
| `--remove` | Takes Orvind out of the agents again. |

To pass an option through the pipe: `curl -fsSL https://raw.githubusercontent.com/orvind/agent-toolkit/main/setup.sh | bash -s -- --status`

Then sign in from the agent, and try: "List my Orvind campaigns."

## Set up by hand

### Claude Code

```
/plugin marketplace add orvind/agent-toolkit
/plugin install orvind@orvind
```

Then run `/mcp`, choose `orvind` and sign in. The skill is available as `/orvind:orvind-playground`, and Claude also uses it on its own when a task matches.

### Codex

```bash
codex mcp add orvind --url https://mcp.orvind.com
codex mcp login orvind
```

### Cursor

In `~/.cursor/mcp.json`:

```json
{ "mcpServers": { "orvind": { "url": "https://mcp.orvind.com" } } }
```

### Claude (web and desktop apps)

Settings, Connectors, Add custom connector, paste `https://mcp.orvind.com`, then sign in.

### Any other agent

Add a remote MCP server with the address `https://mcp.orvind.com` and sign in with your Orvind account.

## Good to know

- **The agent acts as your account.** It can do what you can do in Orvind. Only connect an agent you started yourself.
- **Starting a change needs your approval** every time. In Claude Code this is a prompt from the app itself.
- **A saved version is real.** Writing over a version replaces its game and rebuilds its playables; the agent only does that when you say so in your own words.

## Licence

MIT
