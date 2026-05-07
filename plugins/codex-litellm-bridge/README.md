# Codex LiteLLM Bridge 使用指南

这个插件用于在 Windows 上复刻一套 Codex 多模型配置：

- Codex 启动后仍然进入正常 CLI/TUI。
- 所有自定义模型都走同一个 Codex provider：`litellm`。
- LiteLLM 在本地监听 `http://localhost:<port>/v1`，负责把不同模型名转发到不同上游。
- Codex 的 `model_catalog.json` 会注册自定义模型，确保 `/model` 里能看到并在当前会话内切换。
- LiteLLM 可以通过 Windows 计划任务开机或登录后自启动。

## 重要边界

安装 Codex 插件本身不会自动改系统配置。真正写入配置的是插件里的脚本：

```powershell
.\scripts\codex-litellm-bridge.ps1
```

脚本会在目标电脑上写入：

- Codex `config.toml`
- Codex `model_catalog.json`
- LiteLLM `config.yaml`
- LiteLLM `merge_system.py`
- 用户环境变量里的 API key
- Windows 计划任务 `Codex-LiteLLM-Bridge`
- Windows 计划任务 XML `Codex-LiteLLM-Bridge-Task.xml`

脚本写 Codex 配置前会备份已有 `config.toml`。脚本不会把真实 API key 写进启动脚本；启动脚本会从用户环境变量加载 key 并注入 LiteLLM 进程。

## 插件目录结构

```text
Codex-Model-Bridge/
├─ .agents/plugins/marketplace.json
└─ plugins/codex-litellm-bridge/
   ├─ .codex-plugin/plugin.json
   ├─ README.md
   ├─ agents/openai.yaml
   ├─ assets/
   ├─ scripts/codex-litellm-bridge.ps1
   ├─ skills/codex-litellm-bridge/
   └─ templates/
      ├─ default-models.json
      └─ merge_system.py
```

## 1. 安装插件 marketplace

把整个 `Codex-Model-Bridge` 目录放到目标电脑任意位置，例如：

```text
D:\AI\正在开发中\Codex-Model-Bridge
```

然后添加本地 marketplace：

```powershell
codex plugin marketplace add "D:\AI\正在开发中\Codex-Model-Bridge"
```

如果 Codex UI 里有插件安装入口，也可以从这个 marketplace 里安装 `Codex LiteLLM Bridge`。

## 2. 准备基础环境

目标电脑需要有：

- `codex`
- `python`
- `uv`

检查：

```powershell
codex --version
python --version
uv --version
```

如果没有 LiteLLM，安装脚本可以通过 `-InstallLiteLLM` 调用：

```powershell
uv tool install "litellm[proxy]"
```

## 3. 默认安装

进入插件目录：

```powershell
Set-Location "D:\AI\正在开发中\Codex-Model-Bridge\plugins\codex-litellm-bridge"
```

执行安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 `
  -Action install `
  -InstallLiteLLM `
  -AixorApiKey "sk-你的-AIXOR-key" `
  -ArkApiKey "你的-火山-ARK-key" `
  -MiniMaxApiKey "sk-你的-MiniMax-key" `
  -DaleApiKey "sk-你的-Dale-key" `
  -MimoApiKey "你的-MiMo-key"
```

默认安装位置：

```text
%USERPROFILE%\.codex-litellm-bridge
```

默认 Codex 配置目录：

```text
$env:CODEX_HOME
```

如果没有设置 `CODEX_HOME`，则使用：

```text
%USERPROFILE%\.codex
```

## 4. 自定义安装路径

推荐让朋友安装到独立目录，比如：

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

参数含义：

- `-InstallRoot`：LiteLLM 配置、模型注册表、日志、启动脚本放哪里。
- `-CodexHome`：Codex 的 `config.toml` 和 `model_catalog.json` 放哪里。
- `-Port`：LiteLLM 本地监听端口，默认 `4000`。
- `-InstallLiteLLM`：使用 `uv tool install "litellm[proxy]"` 安装 LiteLLM。

如果用了自定义 `CodexHome`，建议给用户环境变量设置：

```powershell
[Environment]::SetEnvironmentVariable("CODEX_HOME", "D:\AI\codex", "User")
```

安装脚本在传入 `-CodexHome` 时会自动设置用户环境变量 `CODEX_HOME`。设置后重新打开 PowerShell。

## 5. 当前内置模型

内置模型定义在：

```text
templates/default-models.json
```

默认包含：

- `gpt-5.5`
- `gpt-5.4`
- `gpt-5.4-mini`
- `gpt-5.3-codex`
- `gpt-5.2`
- `doubao-code`
- `dale-gpt-5.4`
- `minimax-m2.7-highspeed`
- `mimo-v2.5-pro`
- `mimo-v2.5`

其中 `gpt-5.5-fallback-54` 和 `gpt-5.5-fallback-53codex` 是 fallback 路由，默认不显示在 Codex `/model` 列表里。

## 6. 自定义模型配置

推荐用脚本添加模型，因为它会同时同步：

- LiteLLM `config.yaml`
- Codex `model_catalog.json`

先设置 API key：

```powershell
[Environment]::SetEnvironmentVariable("MY_MODEL_API_KEY", "sk-xxx", "User")
$env:MY_MODEL_API_KEY = "sk-xxx"
```

添加 OpenAI-compatible 模型：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 `
  -Action add-model `
  -InstallRoot "D:\AI\codex-litellm-bridge" `
  -CodexHome "D:\AI\codex" `
  -Name "my-model" `
  -DisplayName "My Model" `
  -Description "My custom OpenAI-compatible model" `
  -UpstreamModel "openai/provider-model-name" `
  -ApiBase "https://example.com/v1" `
  -ApiKeyEnv "MY_MODEL_API_KEY"
```

如果上游只支持 `/v1/chat/completions`，加 `-ChatCompletions`：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 `
  -Action add-model `
  -InstallRoot "D:\AI\codex-litellm-bridge" `
  -CodexHome "D:\AI\codex" `
  -Name "qwen-code" `
  -DisplayName "Qwen Code" `
  -UpstreamModel "openai/qwen-coder-plus" `
  -ApiBase "https://dashscope.aliyuncs.com/compatible-mode/v1" `
  -ApiKeyEnv "DASHSCOPE_API_KEY" `
  -ChatCompletions
```

添加后重启 LiteLLM：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action restart
```

## 7. 参数解释

自定义模型核心参数：

- `-Name`：Codex `/model` 里显示和切换用的模型 slug，例如 `qwen-code`。
- `-DisplayName`：Codex 模型列表里的可读名称。
- `-Description`：模型说明。
- `-UpstreamModel`：LiteLLM 发给上游的真实模型名，通常形如 `openai/xxx`。
- `-ApiBase`：上游或中转地址，例如 `https://example.com/v1`。
- `-ApiKeyEnv`：存放 API key 的环境变量名。
- `-ChatCompletions`：让 LiteLLM 走 chat completions 协议。

## 8. 会话内切换模型

这套方案能在 Codex 当前会话内切换模型的关键点是：

- Codex 只使用一个 provider：`litellm`。
- `/model` 只切换 model slug，不切 provider。
- `model_catalog.json` 把自定义 slug 注册成 `visibility = list`。
- LiteLLM 根据 model slug 把请求转发到不同上游。

安装并启动 LiteLLM 后，进入 Codex：

```powershell
codex
```

在会话里输入：

```text
/model
```

选择或输入模型名，例如：

```text
doubao-code
minimax-m2.7-highspeed
qwen-code
gpt-5.5
```

切换后会继续当前对话上下文。

## 9. 开机自启动

默认安装会注册 Windows 计划任务：

```text
Codex-LiteLLM-Bridge
```

计划任务通过 XML 导入创建，避免 `schtasks /Create /TR ...` 的嵌套引号问题，并显式设置：

- `ExecutionTimeLimit = PT0S`：不被 Windows 默认 72 小时限制终止。
- `DisallowStartIfOnBatteries = false`：电池供电时允许启动。
- `StopIfGoingOnBatteries = false`：切换到电池供电时不停止。
- `MultipleInstancesPolicy = IgnoreNew`：避免重复实例。

手动启用：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action enable-autostart
```

手动禁用：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action disable-autostart
```

## 10. 常用管理命令

查看状态：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action status
```

列出模型：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action list-models
```

同步配置：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action sync
```

启动 LiteLLM：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action start
```

停止 LiteLLM：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action stop
```

重启 LiteLLM：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action restart
```

删除模型：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 `
  -Action remove-model `
  -Name "my-model"
```

## 11. 验证流程

按顺序验证。

检查 LiteLLM 是否监听：

```powershell
netstat -ano | Select-String ":4000"
```

检查 LiteLLM 模型列表：

```powershell
curl.exe -sS http://localhost:4000/v1/models -H "Authorization: Bearer sk-local-anything"
```

检查 Codex 模型目录：

```powershell
codex debug models
```

端到端启动：

```powershell
codex
```

进入后运行：

```text
/model
```

如果能看到自定义模型，说明 `model_catalog.json` 生效。如果切换后能继续对话，说明会话内切换链路正常。

## 12. 常见问题

`/model` 看不到自定义模型：

- 确认运行过 `-Action sync`。
- 确认 `model_catalog_json` 路径写对。
- 确认模型配置里 `catalog_visible` 不是 `false`。

LiteLLM 没启动：

- 运行 `-Action status`。
- 检查端口是否被占用。
- 运行 `-Action restart`。
- 查看 `%InstallRoot%\logs\litellm-error.log`。

API key 报错：

- 确认环境变量名和模型配置里的 `api_key_env` 一致。
- 设置环境变量后重新打开 PowerShell。
- 用 `echo $env:变量名` 检查当前窗口是否能读到。

模型请求协议不兼容：

- 如果上游不支持 responses，添加模型时加 `-ChatCompletions`。
- 对 doubao、minimax 这类模型，通常需要 `-ChatCompletions`。

端口 `4000` 被占用：

- 安装时指定 `-Port 4100`。
- 后续所有管理命令也使用同一个 `-Port 4100`。

## 13. 卸载

先关闭自启动：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action disable-autostart
```

停止 LiteLLM：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\codex-litellm-bridge.ps1 -Action stop
```

删除安装目录，例如：

```powershell
Remove-Item -Recurse -Force "D:\AI\codex-litellm-bridge"
```

如果设置过 `CODEX_HOME`，按需清理：

```powershell
[Environment]::SetEnvironmentVariable("CODEX_HOME", $null, "User")
```

如果不再使用某些 API key，也可以清理：

```powershell
[Environment]::SetEnvironmentVariable("AIXOR_API_KEY", $null, "User")
[Environment]::SetEnvironmentVariable("ARK_API_KEY", $null, "User")
[Environment]::SetEnvironmentVariable("MINIMAX_API_KEY", $null, "User")
[Environment]::SetEnvironmentVariable("DALE_API_KEY", $null, "User")
```

如果脚本备份过旧配置，备份文件会在 Codex 配置目录里，名称类似：

```text
config.toml.bak.20260507123456
```
