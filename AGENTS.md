# Repository Instructions

This repository is for developing and packaging the Codex LiteLLM Bridge only.

Before doing any optimization or development work in this repository, read this
file word by word first and follow it for the entire task.

## Local Machine Safety

Do not modify this machine's active Codex or LiteLLM setup while working on this repository.

Forbidden unless the user explicitly asks for a real local install or runtime change:

- Running `plugins/codex-litellm-bridge/scripts/codex-litellm-bridge.ps1` with actions that write host configuration, including `install`, `sync`, `start`, `restart`, `enable-autostart`, or `disable-autostart`.
- Writing to the active Codex home, such as `%USERPROFILE%\.codex` or the current `CODEX_HOME`.
- Writing to the active LiteLLM home, such as `%USERPROFILE%\.litellm`.
- Creating, changing, or deleting Windows scheduled tasks for LiteLLM/Codex.
- Setting or deleting user environment variables such as `CODEX_HOME`, `LITELLM_API_KEY`, `AIXOR_API_KEY`, `ARK_API_KEY`, `MINIMAX_API_KEY`, or `DALE_API_KEY`.

Allowed validation:

- Static checks, including JSON parsing, PowerShell syntax parsing, Markdown review, and `git diff`.
- Script dry checks that use disposable temp paths only, for example `-InstallRoot "$env:TEMP\..."` and `-CodexHome "$env:TEMP\..."`.

Keep all source edits scoped to this repository unless the user explicitly approves a broader machine-level operation.
