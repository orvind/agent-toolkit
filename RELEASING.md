# Releasing

`main` is where the toolkit is worked on. `release` is what people get: the setup command, the skills and the Claude Code plugin are all read from it. Nothing reaches anyone until `release` moves.

1. On `main`, set the same new version in `.claude-plugin/plugin.json` and `.cursor-plugin/plugin.json`. Claude Code only offers an update when this number changes.
2. Run the checks, and wait for CI to pass on `main`:

   ```bash
   bash tests/check-repo.sh
   ```

   ```bash
   bash tests/run.sh
   ```

   Then install it for real, in throwaway settings folders, and look at the result. This step is not optional: it is the only one that shows what a person ends up with, and CI cannot run it.

   ```bash
   bash tests/release-check.sh
   ```

   Before committing, read `git status` and the diff. Commit the files you changed by name, not everything with `git add -A`: a test run can change a file you were not working on.

3. Move `release` to that commit and tag it:

   ```bash
   git push origin main:release
   ```

   ```bash
   git tag v0.3.0 && git push origin v0.3.0
   ```

4. Create the GitHub release from the tag, with what changed for someone using the toolkit.
5. Check what was published, the same way:

   ```bash
   bash tests/release-check.sh release
   ```

   If it fails, move `release` back to the earlier tag first (below), then fix.

To take a release back, move `release` to the earlier tag: `git push --force origin v0.2.0^{commit}:release`.

Never run a real `claude` or `codex` command from inside this folder while testing. This folder has its own `.mcp.json`, which is the plugin's server, and a command such as `claude mcp remove orvind` run here edits it. That is how 0.3.0 and 0.3.1 were published with no server. `tests/release-check.sh` works in a temporary folder for this reason, and `tests/check-repo.sh` fails when `.mcp.json` does not define the server.

`tests/run.sh` runs the setup script against stand-in agents (`tests/stubs/`) in temporary home folders. Add a case there for anything the script gets wrong, before fixing it.
