# Security

## Reporting a problem

Please report a security problem privately, not in a public issue: on this repository's **Security** tab, choose **Report a vulnerability**. Say what you found, how to reproduce it, and what it lets someone do.

This covers the files in this repository: the setup script, the skills and the plugin manifests. For a problem in Orvind itself (the app, the MCP server at `mcp.orvind.com`, sign-in), report it the same way and we pass it on.

## What the setup script touches

`setup.sh` installs no program and asks for no password. It changes only these, and `--remove` takes them out again:

| Agent | What it changes |
| --- | --- |
| Claude Code | Adds the `orvind` marketplace and plugin through the `claude` command. If the plugin cannot be installed, adds one MCP server named `orvind`. |
| Codex | Adds a `[mcp_servers.orvind]` section to `~/.codex/config.toml`, and the two skill folders under `~/.codex/skills/`. If Codex does not accept the section, the file is put back as it was. |
| Cursor | Adds an `orvind` entry to `~/.cursor/mcp.json`, and the two skill folders under `~/.cursor/skills/`. The file keeps its permissions, stays a link if it was one, and is not rewritten when nothing changes. Other entries in it are not read out or changed. |

It never reads, prints or sends a token. Signing in happens afterwards, in the agent, on Orvind's own page.

## What connecting an agent means

An agent you connect acts as your Orvind account and can do what you can do there. Connect only an agent you started yourself. Starting a change in the Playground spends your team's credits; in Claude Code the app asks you to approve each one.
