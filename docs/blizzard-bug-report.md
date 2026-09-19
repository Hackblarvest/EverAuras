# Bug report: SavedVariables are written on exit but never read back on login

**Product:** World of Warcraft: Forever (Beta)
**Builds affected:** 1.60.1.69893 and 1.60.1.69913 (both tested)
**Category:** User Interface / AddOns
**Severity:** High. No addon can persist any configuration between sessions.

## Summary

The client correctly writes `WTF\Account\<id>\SavedVariables\<AddOn>.lua` on `/reload` and on
exit, but it never executes those files again on the next login. Every addon therefore starts
every session with its saved variables `nil`, and all user configuration is silently lost.

This is not specific to one addon. It affects every addon that declares `## SavedVariables`.

## Steps to reproduce

1. Install any addon that declares `## SavedVariables: FooDB` in its TOC.
2. In the addon, set `FooDB.counter = (FooDB.counter or 0) + 1` on `PLAYER_LOGIN`.
3. Log in, then `/reload` several times.
4. Inspect `WTF\Account\<id>\SavedVariables\<AddOn>.lua` after exiting.

## Expected

`counter` increments on every login: 1, 2, 3, ...
The saved file grows to reflect accumulated state.

## Actual

`counter` is written to disk as `1` every single time. The saved file is correct and
syntactically valid, but its contents are never restored into the global environment.

## Evidence gathered

- A diagnostic placed on the **first executable line of the addon's main chunk** reports the
  saved global as `nil` on every load, including loads where the file on disk demonstrably
  contained data written seconds earlier.
- The same diagnostic appends one timestamped entry per load. Entries never accumulate:
  each saved file contains exactly one entry, always from the current session. If the file
  were being restored, previous entries would still be present.
- Reproduced with `## LoadSavedVariablesFirst: 1` both present and absent. No difference.
- Reproduced across `/reload` and across full game exits.
- Third-party confirmation: independently observed and documented on build 1.60.1.69893
  ("the client writes SavedVariables on exit and never reads them back; proven with a
  pre-seeded file: the global was `nil` from main chunk to logout, in every candidate WTF
  folder").

## Ruled out

- **File validity.** The saved files are well-formed Lua: balanced braces and brackets, no BOM,
  no NUL bytes, no non-ASCII characters, correct trailing newline.
- **Naming.** The SavedVariables filename matches the addon folder name exactly.
- **Permissions.** No read-only attributes on the files, the `SavedVariables` folder, or `WTF`.
- **Duplicate declarations.** No two addons declare the same saved variable name.
- **WTF readability in general.** `Config.wtf` in the same tree is read correctly; CVar changes
  persist across sessions. So the client can read from this directory.
- **Lua errors.** A global error handler installed via `seterrorhandler`, plus BugGrabber,
  captured zero errors during the affected loads. The failure is silent.
- **Addon-specific code.** Confirmed with a minimal purpose-built addon whose only job is to
  increment a counter, as well as with several unrelated third-party addons.

## Workaround in use (for reference only)

Because the client still executes ordinary addon Lua, the saved files can be copied verbatim
into a small addon that loads first, which re-creates the globals before the real addons run.
That this works is further evidence that the data itself is fine and only the restore step is
missing.

## Impact

Until this is fixed, no addon configuration survives a session on the Forever beta. For addon
authors this also makes it impossible to test any feature that depends on persisted state.
