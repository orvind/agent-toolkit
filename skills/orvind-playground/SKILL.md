---
name: orvind-playground
description: |
  How to ask about and change a playable ad's game in Orvind's Playground through the Orvind MCP server. Use this skill when the user wants to: (1) open the Playground on a version or a playable and see its sessions; (2) ask a question about a game; (3) ask for a change to a game, review the plan and start the edit; (4) follow, cancel or preview an edit; (5) save a draft as a new version or over an existing one; (6) continue a Playground session that no longer accepts messages. Also use it when a Playground call is refused and the user asks why. For only finding, playing or downloading a playable with no change, use orvind-playables.
---

# Orvind Playground

Orvind makes playable ads. The Playground is where a game is changed by describing the change in plain words. This skill is the order of work and the rules for doing that through the Orvind MCP server's tools.

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
- The **Playground** runs on a version, or on one playable under a version.

Find the version or playable first, top down, naming what you found at each level so the user can correct you: `list_campaigns` (use `search` when the user named one), `get_campaign` for its versions, and `list_playables` when the user means one playable. The `orvind-playables` skill has the details of finding, and of handing over links and files.

Then open the Playground: `get_playground` with a `version_id`, or with a `playable_id` to work on one playable.

"Open the Playground" or "open it in the Playground" means that call. Do not open a web page or the user's browser for it.

## Reading the Playground

`get_playground` says whether the version can be edited and saved, how many of today's edits are used, and lists the sessions, latest activity first.

For each session, tell the user its title, when it was last active (`last_activity_at` is UTC; say it in everyday terms), and how many drafts it has.

A session with `accepts_messages: false` was made on an earlier copy of the game and is read-only. Say that the game was updated since. Do not send messages to it. When the user wants to go on with it, call `continue_session` and use the session it returns: that one is on the updated game and keeps the chat.

## Asking and changing

`send_message` says something to the Playground: a question, or a change to make. It changes nothing and spends nothing. Leave out `session_id` to start a new session; give it to continue one.

The answer has a `kind`:

| kind | What to do |
| --- | --- |
| `answer` | Give it to the user. |
| `question_back` | Ask the user, then send their reply in the same session. |
| `declined` | Say why, in the Playground's words. |
| `change_proposed` | A plan, sometimes with questions that have numbered options. Show the user the plan and the questions. Start nothing yet. |
| `change_started` | An edit is already running for this message: follow it with `get_run`. |
| none, and `state` is not `completed` | The reply is not ready yet. Read it with `get_conversation`, as below. |

If the plan does not match what the user asked for, say so and suggest rewording. Do not start it.

### When the reply is not ready

Sometimes `send_message` returns before the Playground has replied: the result has no `kind`, and its `next` says to call `get_conversation`. The message was received. Do not send it again.

Call `get_conversation` with the version and the `session_id` from that result, and read the last message. If it still has no reply, wait a few seconds and call again; a reply can take up to two minutes. Then carry on from its `kind` as in the table above.

`get_conversation` is also how to read what was said earlier in a session before continuing it. It lists the messages oldest first; for earlier ones, pass `before` with the `next_before` of the page you have.

### Sending a message again after a failure

Every result carries a `request_key`. When a call failed and the result says it can be tried again, send exactly the same message with that `request_key`, so it cannot be counted twice. Change nothing else: with a different `session_id`, `playable_id`, wording or `edit_level`, the key is refused as a conflict. To send something different, or to send it in another session, leave `request_key` out.

If the same message fails twice, stop. Tell the user what the tool returned and that the problem looks to be on Orvind's side.

`edit_level` sets how a change is made if the message leads to one: `light` (small tweaks, lowest cost), `standard` (any change, the default) or `express` (any change, much faster, highest cost). Use `standard` unless the user asks otherwise.

## Starting a change

`start_change` makes the planned change. It spends the user's team's credits and uses one of the campaign's daily edits.

- Call it only after the user has seen the plan and said, about this plan, that they want it made.
- Pass `answers`: one option number per question, counting from 0. Option 0 is the Playground's suggestion.
- In Claude Code the app itself asks the user to approve this call every time. That is expected: tell the user to approve the prompt. If the call comes back as needing permission, nothing was started and nothing was spent; say so and offer to try again. An allow rule does not skip this prompt.
- Never start changes in a loop. Each one needs the user's own request.

`just_answer` answers a planned message without changing anything, at no cost.

## Following an edit

An edit takes minutes. `get_run` gives its status and the latest progress lines; call it again until it is ready, failed or cancelled, and keep the user posted briefly. `cancel_run` stops a running edit when the user asks.

When it is ready, show the result with `get_preview` and the `run_id`.

## Showing the result

`get_preview` with the version and the edit's `run_id` returns the draft's links. Give `play_url` as a named link: it opens the draft in the browser, ready to play, with no sign-in, for an hour. Say that it is a draft and not saved yet.

`editor_url` (the Playground's page in the Orvind web app) and `download_url` (the game's HTML file) are for when the user asks for the app or the file. The `orvind-playables` skill covers those, and previews of a version or a playable without an edit.

## Saving

A ready edit is only a draft until it is saved.

- `save_version` with a `name` keeps the draft as a new version of the campaign. Call it only when the user asks to save.
- `overwrite_this_version` replaces the saved version the draft was made on and rebuilds its playables. Set it only when the user said, in their own words, to replace or overwrite that version. It cannot be used on the base version.
- A new version starts without playables.

`select_draft` chooses which draft of a session later messages build on.

## When something is refused

Give the user the exact reason the tool returned; it names what happened. Common ones:

- The game was updated: open the Playground again and continue the session with `continue_session`.
- The campaign has used today's edits: new edits become available again within 24 hours. Questions still work.
- The account may not edit this version: the user needs edit access to that campaign's team.
- A save is already in progress: wait for it, then check with `get_run`.

Do not retry a refused call unchanged, and do not work around a refusal with another tool.
