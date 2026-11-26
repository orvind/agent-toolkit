---
name: orvind-playables
description: |
  How to find and get a playable ad from Orvind through the Orvind MCP server, without changing it. Use this skill when the user wants to: (1) see their Orvind campaigns, a campaign's versions, or a version's playables; (2) get a link to play a game, a version or a playable; (3) download a playable's file; (4) get the link to a campaign's page in the Orvind web app; (5) check whether a playable is built. Use it for any "show me", "list", "find", "play", "send me the link", "download" or "open" request about Orvind that asks for no change. For asking about or changing a game, use orvind-playground.
---

# Orvind playables

Orvind makes playable ads. This skill is how to find one and hand it to the user: as a link to play, as a file, or as a page in the Orvind web app. Nothing here changes a game or spends credits.

## Before anything else

The Orvind tools need a sign-in. If they are missing or a call says to authenticate:

- Claude Code: run `/mcp`, choose `orvind`, and authenticate. A browser page titled "Connect … to Orvind?" opens; the user checks it shows their own account and clicks Connect.
- Codex: `codex mcp login orvind --scopes profile,email`.
- Cursor: open Settings, MCP, and sign in on the `orvind` server.

The agent then acts as the user's Orvind account. Never ask the user for a password, token or code.

## How Orvind is organised

Campaign → versions → playables.

- A **campaign** is one game.
- A campaign has **versions**: the base version first, then saved versions v1, v2, ….
- Each version has **playables**: variants of that version's game with their own settings.

## Finding it

Work top down, and name what you found at each level so the user can correct you:

1. `list_campaigns`. Use `search` when the user named a campaign.
2. `get_campaign` for its versions.
3. `list_playables` for a version's playables. Lists are paged: continue with `offset` set to `next_offset` when the user wants more.

Stop at the level the user asked about. "Show my campaigns" needs step 1 only.

When the user's words fit more than one campaign, version or playable, list the matches and ask which one. Do not guess. When they name a campaign and no version, and want the game itself, say which version you are using; the latest saved version that is ready is the usual choice (skip one still being prepared), the base version when there are none.

When listing, give names and what helps the user choose: for versions, which is the base and which are saved; for playables, the name, the tag and whether its file is built.

## Handing it over

`get_preview` returns the links. Give it a `version_id` and:

- nothing more, for the version's game as it is;
- a `playable_id`, for one playable's built file;
- a `run_id`, for the draft of a Playground edit.

It returns three links. Pick by what the user asked for:

| The user wants | Give | What it is |
| --- | --- | --- |
| to play it, see it, try it, share it for a look | `play_url` | Opens the game in a browser, ready to play. No sign-in. |
| the file, to download it, to upload it somewhere | `download_url` | The game's single HTML file. |
| the Orvind app, the editor, their browser | `editor_url` | The page in the Orvind web app. Needs their Orvind sign-in. |

When the user only says "show me" or "open it", give `play_url`.

Rules for the links:

- `play_url` and `download_url` stop working after an hour (`expires_in_seconds`). Say so when giving one, and call `get_preview` again for a fresh link instead of reusing an old one.
- Anyone with a `play_url` or `download_url` can open it during that hour. Mention this when the user plans to pass it on.
- Present each as a named link, for example "Play Supermarket 3D, v2", not as a raw address.
- Do not open links in the user's browser yourself. Give the link and leave opening it to them.
- When `play_url` and `download_url` come back empty, the game could not be linked right now. Say so once, with the note the tool returned, and offer `editor_url`. Do not go through other versions or playables looking for one that works unless the user asks.

## Downloading the file

`download_url` opened in a browser shows the file's source, not the game. So:

- If you can run commands on the user's computer and they asked for the file, save it for them, for example `curl -fsSL -o "<name>.html" "<download_url>"`, into the folder they named or the current one, and tell them where it is. Name the file after the campaign, version and playable.
- Otherwise give the link and say to save it ("Save link as"), then open the saved file to play it.

When `get_preview` returned a `sha256` and you saved the file yourself, check it (`shasum -a 256 "<name>.html"`) and say if it does not match; download it again rather than handing over a file that differs. A playable's built file comes without one, so there is nothing to check.

The file is one HTML page with the whole game inside. Orvind's server gives no other format through these tools; for anything else, point the user to the Orvind web app with `editor_url`.

## When a playable is not ready

- `list_playables` says whether each playable's file is built and the state of its latest build. Tell the user when one is still building or its build failed.
- `get_preview` with a `playable_id` answers that the playable has no built file yet. Say so, and offer the version's game instead (`get_preview` with only the `version_id`). Building a playable is done in the Orvind web app, not through these tools.

## When something is refused

Give the user the exact reason the tool returned. Do not retry a refused call unchanged, and do not work around a refusal with another tool. An account sees only the campaigns of its own teams: when a campaign cannot be found, ask the user to check the name and which Orvind account they signed in with.

## Changing a game

This skill changes nothing. When the user wants to ask about a game's content, change it, or save a version, use the `orvind-playground` skill.
