[CmdletBinding()]
param(
    [ValidateSet("install", "add-model", "remove-model", "list-models", "sync", "start", "stop", "restart", "status", "enable-autostart", "disable-autostart")]
    [string]$Action = "status",

    [string]$InstallRoot = (Join-Path $env:USERPROFILE ".codex-litellm-bridge"),
    [string]$CodexHome = "",
    [ValidateRange(1, 65535)]
    [int]$Port = 4000,
    [string]$DefaultModel = "",
    [bool]$EnableAutostart = $true,
    [switch]$InstallLiteLLM,
    [switch]$Force,

    [string]$AixorApiKey = "",
    [string]$ArkApiKey = "",
    [string]$MiniMaxApiKey = "",
    [string]$DaleApiKey = "",
    [string]$MimoApiKey = "",

    [string]$Name = "",
    [string]$DisplayName = "",
    [string]$Description = "",
    [string]$UpstreamModel = "",
    [string]$ApiBase = "",
    [string]$ApiKeyEnv = "",
    [switch]$ChatCompletions,
    [bool]$CatalogVisible = $true,
    [string[]]$AdditionalDropParams = @()
)

$ErrorActionPreference = "Stop"
$PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TemplatesRoot = Join-Path $PluginRoot "templates"
$TaskName = "Codex-LiteLLM-Bridge"

function Write-Step([string]$Message) {
    Write-Host "[codex-litellm-bridge] $Message"
}

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Assert-Slug([string]$Value, [string]$ParamName) {
    if (!$Value -or $Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        throw "$ParamName must be 1-128 characters and contain only letters, numbers, dots, underscores, or hyphens."
    }
}

function Assert-EnvName([string]$Value, [string]$ParamName) {
    if (!$Value -or $Value -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw "$ParamName must be a valid environment variable name."
    }
}

function Test-CommandExists([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Resolve-CodexHome {
    if ($CodexHome) { return $CodexHome }
    if ($env:CODEX_HOME) { return $env:CODEX_HOME }
    return (Join-Path $env:USERPROFILE ".codex")
}

function Get-Paths {
    $resolvedCodexHome = Resolve-CodexHome
    [pscustomobject]@{
        InstallRoot = $InstallRoot
        CodexHome = $resolvedCodexHome
        LitellmDir = Join-Path $InstallRoot "litellm"
        LogsDir = Join-Path $InstallRoot "logs"
        ModelsPath = Join-Path $InstallRoot "models.json"
        LiteLLMConfig = Join-Path (Join-Path $InstallRoot "litellm") "config.yaml"
        MergeHook = Join-Path (Join-Path $InstallRoot "litellm") "merge_system.py"
        StartScript = Join-Path $InstallRoot "start-litellm.ps1"
        AutostartXml = Join-Path $InstallRoot "Codex-LiteLLM-Bridge-Task.xml"
        CodexConfig = Join-Path $resolvedCodexHome "config.toml"
        CatalogPath = Join-Path $resolvedCodexHome "model_catalog.json"
    }
}

function Get-Registry {
    $paths = Get-Paths
    if (!(Test-Path $paths.ModelsPath)) {
        Ensure-Dir $paths.InstallRoot
        Copy-Item -LiteralPath (Join-Path $TemplatesRoot "default-models.json") -Destination $paths.ModelsPath -Force
    }
    return Get-Content -LiteralPath $paths.ModelsPath -Raw | ConvertFrom-Json
}

function Save-Registry($Registry) {
    $paths = Get-Paths
    Ensure-Dir $paths.InstallRoot
    $Registry | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $paths.ModelsPath -Encoding UTF8
}

function Set-UserEnvIfPresent([string]$Key, [string]$Value) {
    if ($Value) {
        Assert-EnvName $Key "Environment variable name"
        [Environment]::SetEnvironmentVariable($Key, $Value, "User")
        Set-Item -Path "Env:$Key" -Value $Value
    }
}

function Quote-Yaml([string]$Value) {
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Get-ModelEnvNames {
    $registry = Get-Registry
    $names = @("LITELLM_API_KEY")
    $names += @($registry.models | Where-Object { $_.api_key_env } | Select-Object -ExpandProperty api_key_env)
    return @($names | Where-Object { $_ } | Select-Object -Unique)
}

function Write-LiteLLMConfig {
    $paths = Get-Paths
    $registry = Get-Registry
    Ensure-Dir $paths.LitellmDir
    Copy-Item -LiteralPath (Join-Path $TemplatesRoot "merge_system.py") -Destination $paths.MergeHook -Force

    $lines = @("model_list:")
    foreach ($model in @($registry.models)) {
        $lines += "  - model_name: $($model.name)"
        $lines += "    litellm_params:"
        $lines += "      model: $(Quote-Yaml $model.upstream_model)"
        $lines += "      api_base: $(Quote-Yaml $model.api_base)"
        $lines += "      api_key: os.environ/$($model.api_key_env)"
        if ($model.use_chat_completions_api -eq $true) {
            $lines += "      use_chat_completions_api: true"
        }
        if ($model.stream_timeout) {
            $lines += "      stream_timeout: $($model.stream_timeout)"
        }
        if ($model.max_retries) {
            $lines += "      max_retries: $($model.max_retries)"
        }
        if ($model.additional_drop_params) {
            $items = @($model.additional_drop_params) | ForEach-Object { Quote-Yaml $_ }
            $lines += "      additional_drop_params: [$($items -join ', ')]"
        }
        $lines += ""
    }

    $lines += "router:"
    $lines += "  strategy: ""latency-based-routing"""
    $lines += "  allowed_fails: 3"
    $lines += "  timeout: 120"
    $lines += ""
    $lines += "litellm_settings:"
    $lines += "  drop_params: true"
    $lines += "  callbacks: merge_system.proxy_handler_instance"
    $lines += "  request_timeout: 300"
    $lines += "  num_retries: 2"
    if ($registry.fallbacks) {
        $lines += "  fallbacks:"
        foreach ($fallback in @($registry.fallbacks)) {
            $targets = @($fallback.to) | ForEach-Object { Quote-Yaml $_ }
            $lines += "    - $($fallback.from): [$($targets -join ', ')]"
        }
    }
    $lines += ""
    $lines += "server_settings:"
    $lines += "  port: $Port"

    $lines -join [Environment]::NewLine | Set-Content -LiteralPath $paths.LiteLLMConfig -Encoding UTF8
    Write-Step "Wrote LiteLLM config: $($paths.LiteLLMConfig)"
}

function Set-JsonProp($Object, [string]$Name, $Value) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-CodexCatalogJson {
    $paths = Get-Paths
    if (Test-Path $paths.CatalogPath) {
        return Get-Content -LiteralPath $paths.CatalogPath -Raw | ConvertFrom-Json
    }
    Push-Location $env:USERPROFILE
    try {
        $raw = (& codex debug models 2>$null | Out-String)
    } finally {
        Pop-Location
    }
    $start = $raw.IndexOf("{")
    if ($start -lt 0) {
        throw "codex debug models did not return JSON. Install Codex first or provide an existing model_catalog.json."
    }
    return $raw.Substring($start) | ConvertFrom-Json
}

function Sync-CodexCatalog {
    $paths = Get-Paths
    $registry = Get-Registry
    Ensure-Dir $paths.CodexHome

    $catalog = Get-CodexCatalogJson
    $models = @($catalog.models)
    $template = @($models | Where-Object { $_.slug -eq $registry.default_model })[0]
    if (-not $template) {
        $template = @($models | Where-Object { $_.visibility -eq "list" })[0]
    }
    if (-not $template) {
        $template = $models[0]
    }
    if (-not $template) {
        throw "Could not find a template model in Codex catalog."
    }

    foreach ($model in @($registry.models | Where-Object { $_.catalog_visible -ne $false })) {
        $entry = @($models | Where-Object { $_.slug -eq $model.name })[0]
        if (-not $entry) {
            $entry = ($template | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
            $models += $entry
        }
        Set-JsonProp $entry "slug" $model.name
        Set-JsonProp $entry "display_name" $model.display_name
        Set-JsonProp $entry "description" $model.description
        Set-JsonProp $entry "visibility" "list"
        Set-JsonProp $entry "priority" 100
        Set-JsonProp $entry "apply_patch_tool_type" "function"
        Set-JsonProp $entry "supports_search_tool" $false
        Set-JsonProp $entry "availability_nux" $null
        Set-JsonProp $entry "upgrade" $null
    }

    Set-JsonProp $catalog "models" $models
    $catalog | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $paths.CatalogPath -Encoding UTF8
    Write-Step "Synced Codex model catalog: $($paths.CatalogPath)"
}

function Write-CodexConfig {
    $paths = Get-Paths
    $registry = Get-Registry
    Ensure-Dir $paths.CodexHome

    $model = if ($DefaultModel) { $DefaultModel } elseif ($registry.default_model) { $registry.default_model } else { "gpt-5.5" }
    $catalogForToml = $paths.CatalogPath.Replace("\", "/")
    $content = @"
model = "$model"
model_provider = "litellm"
personality = "pragmatic"
model_catalog_json = "$catalogForToml"
model_reasoning_effort = "medium"

[model_providers.aixor]
name = "Aixor"
base_url = "https://aixor.org/v1"
env_key = "AIXOR_API_KEY"
wire_api = "responses"

[model_providers.litellm]
name = "LiteLLM Local Proxy"
base_url = "http://localhost:$Port/v1"
env_key = "LITELLM_API_KEY"
wire_api = "responses"
"@

    if ((Test-Path $paths.CodexConfig) -and ((Get-Content -LiteralPath $paths.CodexConfig -Raw) -ne $content)) {
        $backup = "$($paths.CodexConfig).bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -LiteralPath $paths.CodexConfig -Destination $backup -Force
        Write-Step "Backed up existing Codex config: $backup"
    }
    $content | Set-Content -LiteralPath $paths.CodexConfig -Encoding UTF8
    Write-Step "Wrote Codex config: $($paths.CodexConfig)"
}

function Write-StartScript {
    $paths = Get-Paths
    $envLoadLines = @(
        Get-ModelEnvNames | ForEach-Object {
            "Set-EnvFromUser ""$_"""
        }
    ) -join [Environment]::NewLine
    Ensure-Dir $paths.InstallRoot
    Ensure-Dir $paths.LogsDir
    $script = @"
param([switch]`$ForceStopLiteLLM)
`$ErrorActionPreference = "Stop"
Start-Sleep -Seconds 30
`$logFile = "$($paths.LogsDir)\litellm-startup.log"
Add-Content -Path `$logFile -Value "`n[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting LiteLLM on port $Port"

function Set-EnvFromUser([string]`$Name) {
    if ([Environment]::GetEnvironmentVariable(`$Name, "Process")) { return }
    `$value = [Environment]::GetEnvironmentVariable(`$Name, "User")
    if (`$value) {
        Set-Item -Path "Env:`$Name" -Value `$value
    }
}

$envLoadLines

`$portInUse = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
if (`$portInUse -and `$ForceStopLiteLLM) {
    Get-Process -Name "litellm" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
}
Set-Location "$($paths.LitellmDir)"
`$commonLitellm = Join-Path `$env:USERPROFILE ".local\bin\litellm.exe"
if (Test-Path `$commonLitellm) {
    `$processFile = `$commonLitellm
    `$processArgs = @("--config", "$($paths.LiteLLMConfig)", "--port", "$Port")
} elseif ((`$litellmCommand = Get-Command litellm -ErrorAction SilentlyContinue)) {
    `$processFile = `$litellmCommand.Source
    `$processArgs = @("--config", "$($paths.LiteLLMConfig)", "--port", "$Port")
} elseif (Get-Command uv -ErrorAction SilentlyContinue) {
    `$processFile = "uv"
    `$processArgs = @("tool", "run", "litellm", "--config", "$($paths.LiteLLMConfig)", "--port", "$Port")
} else {
    throw "Neither litellm nor uv was found in PATH. Install LiteLLM first."
}
Start-Process -FilePath `$processFile -ArgumentList `$processArgs -WindowStyle Hidden -RedirectStandardOutput "$($paths.LogsDir)\litellm.log" -RedirectStandardError "$($paths.LogsDir)\litellm-error.log"
"@
    $script | Set-Content -LiteralPath $paths.StartScript -Encoding UTF8
    Write-Step "Wrote LiteLLM start script: $($paths.StartScript)"
}

function Write-AutostartXml {
    $paths = Get-Paths
    Ensure-Dir $paths.InstallRoot
    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($paths.StartScript)`" -ForceStopLiteLLM"
    $escapedArguments = [Security.SecurityElement]::Escape($arguments)
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Start LiteLLM for Codex custom model switching.</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>false</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>$escapedArguments</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    $xml | Set-Content -LiteralPath $paths.AutostartXml -Encoding Unicode
    Write-Step "Wrote scheduled task XML: $($paths.AutostartXml)"
}

function Sync-Bridge {
    Write-LiteLLMConfig
    Sync-CodexCatalog
    Write-CodexConfig
    Write-StartScript
}

function Enable-Autostart {
    $paths = Get-Paths
    Write-StartScript
    Write-AutostartXml
    schtasks.exe /Create /TN $TaskName /XML $paths.AutostartXml /F | Out-Null
    Write-Step "Registered scheduled task from XML: $TaskName"
}

function Disable-Autostart {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Step "Removed scheduled task: $TaskName"
    }
}

function Start-Bridge {
    $paths = Get-Paths
    if (!(Test-Path $paths.StartScript)) { Write-StartScript }
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $paths.StartScript, "-ForceStopLiteLLM" -WindowStyle Hidden
    Write-Step "Started LiteLLM bridge."
}

function Stop-Bridge {
    Get-Process -Name "litellm" -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Step "Stopped litellm.exe processes."
}

function Show-Status {
    $paths = Get-Paths
    Write-Host "InstallRoot: $($paths.InstallRoot)"
    Write-Host "CodexHome:   $($paths.CodexHome)"
    Write-Host "Port:        $Port"
    $listen = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    Write-Host "Listening:   $([bool]$listen)"
    Write-Host "LiteLLM cfg: $([bool](Test-Path $paths.LiteLLMConfig)) $($paths.LiteLLMConfig)"
    Write-Host "Task XML:    $([bool](Test-Path $paths.AutostartXml)) $($paths.AutostartXml)"
    Write-Host "Codex cfg:   $([bool](Test-Path $paths.CodexConfig)) $($paths.CodexConfig)"
    Write-Host "Catalog:     $([bool](Test-Path $paths.CatalogPath)) $($paths.CatalogPath)"
    Write-Host "Autostart:   $([bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) $TaskName"
    if (Test-Path $paths.ModelsPath) {
        $registry = Get-Registry
        Write-Host "Models:      $((@($registry.models | Where-Object { $_.catalog_visible -ne $false }).name) -join ', ')"
        $missingEnv = @($registry.models | Where-Object {
            $_.api_key_env -and
            -not [Environment]::GetEnvironmentVariable($_.api_key_env, "User") -and
            -not [Environment]::GetEnvironmentVariable($_.api_key_env, "Process")
        } | Select-Object -ExpandProperty api_key_env -Unique)
        if ($missingEnv.Count -gt 0) {
            Write-Host "Missing env: $($missingEnv -join ', ')"
        }
    }
}

function Add-Model {
    if (!$Name -or !$UpstreamModel -or !$ApiBase -or !$ApiKeyEnv) {
        throw "add-model requires -Name, -UpstreamModel, -ApiBase, and -ApiKeyEnv."
    }
    Assert-Slug $Name "-Name"
    Assert-EnvName $ApiKeyEnv "-ApiKeyEnv"
    if ($ApiBase -notmatch '^https?://') {
        throw "-ApiBase must start with http:// or https://."
    }
    $registry = Get-Registry
    $existing = @($registry.models | Where-Object { $_.name -eq $Name })[0]
    if ($existing -and !$Force) {
        throw "Model '$Name' already exists. Use -Force to replace it."
    }
    if ($existing) {
        $registry.models = @($registry.models | Where-Object { $_.name -ne $Name })
    }
    $entry = [ordered]@{
        name = $Name
        display_name = $(if ($DisplayName) { $DisplayName } else { $Name })
        description = $(if ($Description) { $Description } else { "Custom model routed through LiteLLM." })
        upstream_model = $UpstreamModel
        api_base = $ApiBase
        api_key_env = $ApiKeyEnv
        catalog_visible = $CatalogVisible
    }
    if ($ChatCompletions) { $entry.use_chat_completions_api = $true }
    if ($AdditionalDropParams.Count -gt 0) { $entry.additional_drop_params = $AdditionalDropParams }
    $registry.models = @($registry.models) + ([pscustomobject]$entry)
    Save-Registry $registry
    Sync-Bridge
}

function Remove-Model {
    if (!$Name) { throw "remove-model requires -Name." }
    Assert-Slug $Name "-Name"
    $registry = Get-Registry
    $registry.models = @($registry.models | Where-Object { $_.name -ne $Name })
    Save-Registry $registry
    Sync-Bridge
}

function Install-Bridge {
    $paths = Get-Paths
    Ensure-Dir $paths.InstallRoot
    Ensure-Dir $paths.LitellmDir
    Ensure-Dir $paths.LogsDir
    if ($CodexHome) {
        [Environment]::SetEnvironmentVariable("CODEX_HOME", $CodexHome, "User")
        $env:CODEX_HOME = $CodexHome
        Write-Step "Set user CODEX_HOME: $CodexHome"
    }
    if (!(Test-Path $paths.ModelsPath) -or $Force) {
        Copy-Item -LiteralPath (Join-Path $TemplatesRoot "default-models.json") -Destination $paths.ModelsPath -Force
    }

    Set-UserEnvIfPresent "AIXOR_API_KEY" $AixorApiKey
    Set-UserEnvIfPresent "ARK_API_KEY" $ArkApiKey
    Set-UserEnvIfPresent "MINIMAX_API_KEY" $MiniMaxApiKey
    Set-UserEnvIfPresent "DALE_API_KEY" $DaleApiKey
    Set-UserEnvIfPresent "MIMO_API_KEY" $MimoApiKey
    if (![Environment]::GetEnvironmentVariable("LITELLM_API_KEY", "User")) {
        [Environment]::SetEnvironmentVariable("LITELLM_API_KEY", "sk-local-anything", "User")
        $env:LITELLM_API_KEY = "sk-local-anything"
    }

    if ($InstallLiteLLM) {
        if (!(Test-CommandExists "uv")) {
            throw "uv is required for -InstallLiteLLM but was not found in PATH. Install uv first or rerun without -InstallLiteLLM."
        }
        Write-Step "Installing LiteLLM with uv."
        uv tool install "litellm[proxy]"
    }

    Sync-Bridge
    if ($EnableAutostart) { Enable-Autostart }
    Write-Step "Install complete. Restart PowerShell before launching codex if this was the first install."
}

switch ($Action) {
    "install" { Install-Bridge }
    "add-model" { Add-Model }
    "remove-model" { Remove-Model }
    "list-models" { (Get-Registry).models | Select-Object name, display_name, api_base, api_key_env, catalog_visible | Format-Table -AutoSize }
    "sync" { Sync-Bridge }
    "start" { Start-Bridge }
    "stop" { Stop-Bridge }
    "restart" { Stop-Bridge; Start-Sleep -Seconds 2; Start-Bridge }
    "status" { Show-Status }
    "enable-autostart" { Enable-Autostart }
    "disable-autostart" { Disable-Autostart }
}
