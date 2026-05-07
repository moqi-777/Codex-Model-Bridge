---
name: codex-litellm-bridge
description: Install and manage a Windows Codex + LiteLLM bridge that enables Codex CLI to route through localhost LiteLLM, expose custom models in /model, switch models inside an ongoing Codex conversation, add/remove custom model entries, sync model_catalog.json, and register LiteLLM autostart. Use when the user asks to install, package, debug, or manage Codex LiteLLM multi-model routing, custom Codex models, in-session model switching, LiteLLM proxy routing, or Codex multi-model configuration.
---

# Codex LiteLLM Bridge

Use this skill to install or manage the bundled Windows bridge. The bridge has four moving parts:

- Codex config points one provider named `litellm` at `http://localhost:<port>/v1`.
- LiteLLM maps model names such as `gpt-5.5`, `doubao-code`, and custom slugs to upstream OpenAI-compatible APIs.
- `model_catalog.json` registers those slugs with `visibility = list`, which makes `/model` show them and allows switching inside the current Codex session.
- A Windows scheduled task starts LiteLLM at logon so plain `codex` works after reboot. The task is registered from XML so it can disable the default 72-hour execution timeout and battery restrictions.

## Safety

Do not run the installer on the current machine unless the user explicitly asks. The installer intentionally writes Codex config, model catalog, LiteLLM config, user environment variables, and a scheduled task on the target machine.

The installer backs up an existing `config.toml` before replacing it. It does not write API keys into script files; it stores provided keys as user environment variables and the generated LiteLLM start script loads them into the LiteLLM process environment.

## Main Script

Use the bundled script:

```powershell
<plugin-root>\scripts\codex-litellm-bridge.ps1
```

Common actions:

```powershell
# Install with default model set and LiteLLM autostart.
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action install -InstallLiteLLM `
  -AixorApiKey "sk-..." -ArkApiKey "..." -MiniMaxApiKey "..." -DaleApiKey "..." -MimoApiKey "..."

# Show bridge status.
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action status

# Add a custom OpenAI-compatible model and sync both LiteLLM and Codex catalog.
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action add-model `
  -Name "my-model" `
  -DisplayName "My Model" `
  -UpstreamModel "openai/provider-model-name" `
  -ApiBase "https://example.com/v1" `
  -ApiKeyEnv "MY_MODEL_API_KEY"

# Add a chat-completions-only model.
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action add-model `
  -Name "my-chat-model" `
  -UpstreamModel "openai/provider-model-name" `
  -ApiBase "https://example.com/v1" `
  -ApiKeyEnv "MY_CHAT_MODEL_API_KEY" `
  -ChatCompletions

# Restart LiteLLM after manual edits.
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action restart
```

## Install Defaults

Default install root:

```text
%USERPROFILE%\.codex-litellm-bridge
```

Default Codex home:

```text
$env:CODEX_HOME if set, otherwise %USERPROFILE%\.codex
```

Default models are defined in `templates/default-models.json`. Add or remove models through the script so `config.yaml` and `model_catalog.json` stay in sync.

When `-CodexHome` is passed to `-Action install`, the script sets the user `CODEX_HOME` environment variable to that path. Ask the user to reopen PowerShell before launching `codex`.

## Verification

After install, check these layers in order:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action status
curl.exe -sS http://localhost:4000/v1/models -H "Authorization: Bearer sk-local-anything"
codex debug models
codex
```

Inside Codex, use `/model` and confirm custom models appear. Switching is expected to continue the current conversation because every model slug uses the same Codex provider, `litellm`; LiteLLM handles routing behind that provider.
