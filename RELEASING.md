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

3. Move `release` to that commit and tag it:

   ```bash
   git push origin main:release
   ```

   ```bash
   git tag v0.3.0 && git push origin v0.3.0
   ```

4. Create the GitHub release from the tag, with what changed for someone using the toolkit.
5. Check the published command on a machine, or in throwaway settings folders: `curl -fsSL https://raw.githubusercontent.com/orvind/agent-toolkit/release/setup.sh | bash -s -- --status`

To take a release back, move `release` to the earlier tag: `git push --force origin v0.2.0^{commit}:release`.

`tests/run.sh` runs the setup script against stand-in agents (`tests/stubs/`) in temporary home folders. Add a case there for anything the script gets wrong, before fixing it.
