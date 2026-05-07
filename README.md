# Codex LiteLLM Bridge Marketplace

这是一个可分发的 Codex 本地插件 marketplace，用于安装 `codex-litellm-bridge` 插件。

插件用途：

- 在 Windows 上安装和管理 LiteLLM 本地代理。
- 让 Codex 通过单一 `litellm` provider 使用多个上游模型。
- 生成并同步 Codex `model_catalog.json`，让自定义模型显示在 `/model` 列表里。
- 支持在当前 Codex 会话内切换自定义模型并继续对话。
- 注册 Windows 计划任务，让 LiteLLM 自动启动。

## 目录结构

```text
.
├─ .agents/plugins/marketplace.json
└─ plugins/codex-litellm-bridge/
   ├─ .codex-plugin/plugin.json
   ├─ README.md
   ├─ scripts/codex-litellm-bridge.ps1
   ├─ skills/codex-litellm-bridge/
   ├─ templates/
   └─ assets/
```

## 安装 marketplace

把仓库克隆到目标电脑，例如：

```powershell
git clone https://github.com/moqi-777/Codex-Model-Bridge D:\AI\正在开发中\Codex-Model-Bridge
```

添加到 Codex：

```powershell
codex plugin marketplace add "D:\AI\正在开发中\Codex-Model-Bridge"
```

然后在 Codex 插件入口安装 `Codex LiteLLM Bridge`。如果当前 Codex 版本没有图形化安装入口，也可以直接使用插件目录里的脚本。

## 安装桥接配置

进入插件目录：

```powershell
Set-Location "D:\AI\正在开发中\Codex-Model-Bridge\plugins\codex-litellm-bridge"
```

推荐安装到独立路径：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 `
  -Action install `
  -InstallRoot "D:\AI\codex-litellm-bridge" `
  -CodexHome "D:\AI\codex" `
  -Port 4000 `
  -InstallLiteLLM `
  -AixorApiKey "sk-你的-AIXOR-key" `
  -ArkApiKey "你的-火山-ARK-key" `
  -MiniMaxApiKey "sk-你的-MiniMax-key" `
  -DaleApiKey "sk-你的-Dale-key" `
  -MimoApiKey "你的-MiMo-key"
```

脚本会备份已有 Codex `config.toml`，再写入新的 LiteLLM provider 配置。真实 API key 会写入用户环境变量，不会写进脚本文件；LiteLLM 启动脚本会在进程启动时从用户环境变量加载所需 key。

完整使用说明见：

```text
plugins/codex-litellm-bridge/README.md
```

## 自定义模型

示例：

```powershell
[Environment]::SetEnvironmentVariable("MY_MODEL_API_KEY", "sk-xxx", "User")
$env:MY_MODEL_API_KEY = "sk-xxx"

powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 `
  -Action add-model `
  -InstallRoot "D:\AI\codex-litellm-bridge" `
  -CodexHome "D:\AI\codex" `
  -Name "my-model" `
  -DisplayName "My Model" `
  -UpstreamModel "openai/provider-model-name" `
  -ApiBase "https://example.com/v1" `
  -ApiKeyEnv "MY_MODEL_API_KEY"
```

如果上游只支持 chat completions：

```powershell
-ChatCompletions
```

## 验证

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action status
curl.exe -sS http://localhost:4000/v1/models -H "Authorization: Bearer sk-local-anything"
codex debug models
codex
```

进入 Codex 后使用：

```text
/model
```

应能看到插件注册的自定义模型。

## 安全说明

- 仓库不应提交真实 API key。
- `sk-local-anything` 是本地 LiteLLM 占位 token，不是上游模型密钥。
- 不要提交日志、临时目录、备份配置、生成后的本机安装目录。

## License

MIT
