# Index Translate Bridge

[![Release](https://img.shields.io/github/v/release/Siyin22/IndexTranslateBridge?label=Release)](https://github.com/Siyin22/IndexTranslateBridge/releases/latest)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%2F%2011-0078D6)](https://github.com/Siyin22/IndexTranslateBridge)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB)](https://www.python.org/downloads/windows/)
[![License](https://img.shields.io/github/license/Siyin22/IndexTranslateBridge)](LICENSE)

面向 Windows 的本地 OpenAI 兼容转接工具，用于将哔哩哔哩官方 [Index-Translate](https://github.com/bilibili/Index-Translate) 翻译服务接入浏览器扩展、划词/截图翻译软件、桌面 AI 客户端及自定义脚本。

本项目直接复用官方仓库未修改的 [`call_api.py`](https://github.com/bilibili/Index-Translate/blob/main/inference/llm/call_api.py) 作为转接核心，并在外层补齐了 Windows 一键后台启停、登录后静默自启动与上游脚本安全更新能力。

## 核心特性

- **零第三方依赖**：仅依赖 Python 标准库，无需 `pip install`，也无需下载本地模型或配置显卡。
- **缓解扩展直连风控**：将客户端请求先发往 `127.0.0.1`，再由官方脚本直连上游接口，减少浏览器扩展直连 B 站接口时触发 `412` 风控的问题。
- **上游默认直连**：转接服务内部显式绕过系统代理，不修改系统网络设置，避免国内接口绕行代理导致超时或异常。
- **开箱适配翻译场景**：支持流式输出（SSE）与 `/v1/models` 模型列表；未显式指定时默认关闭思考模式（`enable_thinking: false`）并设置 `temperature: 0.0`，防止推理过程污染译文。
- **安全的启停与自启管理**：支持双击一键后台运行、关闭窗口不中断；关闭时核验 PID 与脚本命令行防误杀；支持 Windows 登录后无弹窗静默自启。
- **可回滚的上游更新**：一键检查官方 `call_api.py` 更新，先校验 Python 语法与入口函数签名，再自动备份并原子替换，同时同步来源提交记录。

## 工作原理

```text
支持 OpenAI Chat Completions 的客户端
                │
                ▼
本机转接服务  http://127.0.0.1:8080/v1   (仅监听本机回环)
                │
                ▼  直连（不走系统代理）
B 站 Index-Translate 官方公开 API
```

> [!NOTE]
> - 实际翻译在 B 站服务器在线完成，需要联网，待译文本会发送至上游官方接口。
> - 本机中转可解决部分浏览器扩展直连时的来源头兼容与 `412` 问题，但无法保证规避所有上游风控、限流或网络波动。

## 运行要求

- **操作系统**：Windows 10 / 11（当前启停与自启脚本仅面向 Windows）。
- **Python 环境**：Python 3.10 或更高版本（建议从 [Python 官网](https://www.python.org/downloads/windows/) 安装，并启用 **Python Launcher** 或勾选 **Add python.exe to PATH**）。
- **端口与网络**：本机 `8080` 端口未被占用（可按需修改），且当前网络可直连 `index-translate.bilibili.com`。

可在终端运行以下命令确认 Python 可用：

```powershell
py -3 --version
# 若未安装 py 启动器，则执行：
python --version
```

## 快速开始

### 1. 下载并解压

前往 [Latest Release](https://github.com/Siyin22/IndexTranslateBridge/releases/latest)，在 **Assets** 中下载 `IndexTranslateBridge-<版本号>-windows.zip` 并解压到本地任意目录（请先解压，不要在压缩包内直接双击脚本）。

> 也可以在仓库主页点击 **Code → Download ZIP** 下载源码。发布包不包含 Python 运行时，仍需本机已安装 Python 3.10+。

### 2. 启动转接服务

双击项目目录中的 **`Start-IndexTranslate.cmd`**。看到以下输出即表示启动成功：

```text
Bridge started. You may close this window.
Base URL: http://127.0.0.1:8080/v1
API Key: index
Model: Index-Translate-35B-A3B
```

此时可以直接关闭命令行窗口，服务会继续在后台运行。若服务已在运行，再次启动会提示 `Bridge already running`。

也可以在项目目录的终端中手动启动：

```powershell
py -3 -I scripts\launch.py
# 若没有 py 命令，改用：
python -I scripts\launch.py
```

### 3. 配置客户端

在支持 **OpenAI Chat Completions** 协议且允许自定义地址的客户端中新增一个服务，按下表填写：

| 配置项 | 填写内容 | 说明 |
| --- | --- | --- |
| 服务名称 | `Index 翻译`（自定义） | 仅用于区分展示 |
| 接口类型 | OpenAI 兼容 / Chat Completions | 优先选择 Chat Completions 协议 |
| Base URL | `http://127.0.0.1:8080/v1` | 若客户端要求完整请求地址，填 `http://127.0.0.1:8080/v1/chat/completions` |
| API Key | `index` | 占位字符串，本地服务不校验也不会转发给上游 |
| 模型 ID | `Index-Translate-35B-A3B` | 默认推荐；亦可按需切换其他规格模型 |

**可用模型列表**（本机服务支持 `GET /v1/models` 返回以下模型）：

| 模型 ID | 定位说明 |
| --- | --- |
| `Index-Translate-35B-A3B` | 默认推荐，旗舰版本，适合复杂句式与高质量翻译 |
| `Index-Translate-9B` | 均衡版本 |
| `Index-Translate-2B` | 轻量快速版本 |

保存后点击测试连接，并在客户端中将该服务设为默认翻译引擎，设置目标语言或翻译提示词（例如：`请将以下文本翻译为简体中文，只输出译文`）。

## 客户端配置示例

> [!TIP]
> 不同软件的菜单名称可能随版本调整，只要支持 OpenAI 兼容（Chat Completions）自定义端点，均可参照上节参数接入（例如沉浸式翻译、桌面 AI 客户端及自写脚本）。以下以两款常用工具为例：

### 陪读蛙（Read Frog）

1. 打开设置，进入 **API 提供商 → 添加提供商**。
2. 选择 **自定义 Chat Complete**（或基于 Chat Completions 协议的 OpenAI 兼容项）。
3. 填入 Base URL（`http://127.0.0.1:8080/v1`）、API Key（`index`）与模型 ID（`Index-Translate-35B-A3B`，若下拉列表无此项可直接手填）。
4. 测试连接通过后，在 **功能提供商** 中为网页翻译、划词翻译等功能选择该提供商，并设置目标语言（如简体中文）。

### SnowShot

1. 打开设置，进入 **自定义模型 → 添加模型**（旧版可能位于 **设置 → 功能设置 → AI 对话 → 添加 API 配置**）。
2. 按上表填入接口信息；如果界面中存在「推理支持 / 思考模式」开关，建议关闭。
3. 在 **翻译** 设置中将翻译引擎切换为刚添加的模型，并选择目标语言。
4. 若使用支持插件管理的版本，请确认已安装 **翻译、文本识别、AI 对话** 插件。

## 日常管理与进阶配置

### 关闭服务

双击 **`Stop-IndexTranslate.cmd`**，出现 `Bridge stopped` 提示即表示已停止；重复执行会提示 `Bridge is already stopped`。

关闭脚本会先读取 `runtime\bridge.pid`，核对目标进程是否为 `python.exe` / `pythonw.exe` 且命令行匹配当前项目的 `scripts\run_bridge.py`，确认无误后才会终止进程，避免因系统复用 PID 而误杀其他程序。

停止后，客户端配置无需改动，下次直接重新运行 `Start-IndexTranslate.cmd` 即可恢复。

### 设置 Windows 开机静默自启动

项目自带 `AutoStart-IndexTranslate.vbs`，可在当前用户登录 Windows 时静默拉起服务（无黑框闪现），并自动查找本机的 `py.exe` 或 `python.exe`，不绑定固定安装路径。如果服务已在运行，启动脚本会自动检测并退出，不会重复占用端口。

**开启步骤：**

1. 确认在终端运行 `py -3 --version` 或 `python --version` 正常。
2. 在项目目录打开 PowerShell，执行以下命令在当前用户的「启动」文件夹创建快捷方式：

```powershell
$project = (Get-Location).Path
$startup = [Environment]::GetFolderPath('Startup')
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut((Join-Path $startup 'IndexTranslateBridge 自动启动.lnk'))
$link.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$link.Arguments = '//nologo "' + (Join-Path $project 'AutoStart-IndexTranslate.vbs') + '"'
$link.WorkingDirectory = $project
$link.Save()
```

3. 注销或重启后，服务将在后台自动就绪。如自启动异常，可查看 `runtime\autostart.log`。

**取消自启动**：按 `Win + R` 输入 `shell:startup` 回车，删除其中的 `IndexTranslateBridge 自动启动.lnk` 即可。

### 检查并更新官方脚本

双击 **`Update-IndexTranslate.cmd`**，或在项目目录的 PowerShell 中执行：

```powershell
# 检查并在确认后更新
.\scripts\update_call_api.ps1

# 仅检查差异，不提示覆盖
.\scripts\update_call_api.ps1 -CheckOnly
```

> 双击入口会自动优先调用 PowerShell 7（`pwsh`），未安装时回退至 Windows PowerShell 5.1，且仅为本次运行绕过执行策略，不修改系统策略。

**更新机制说明：**

1. **网络策略**：检查 GitHub 上游提交与拉取文件时，若检测到本机 `127.0.0.1:7897` 存在可用 HTTP 代理则优先使用，代理不可用或连接失败时自动回退直连（不影响翻译服务本身的直连策略）。
2. **安全预检**：发现上游内容变化后，会展示本地与上游的提交哈希并等待输入 `Y` 确认；确认后在不执行下载代码的前提下，先用 Python AST 校验语法及 `run_proxy_server(port=8080, host='127.0.0.1')` 签名兼容性。
3. **备份与生效**：写入前会将原 `scripts\call_api.py` 和 `THIRD_PARTY_NOTICES.md` 备份至 `runtime\update-backups\<时间戳>-<随机ID>\`，随后原子替换并同步来源提交号；若写入失败会自动尝试恢复。更新不会自动重启服务，完成后请依次运行 `Stop-IndexTranslate.cmd` 和 `Start-IndexTranslate.cmd` 使新版生效。

### 修改默认监听端口

<details>
<summary>点击展开：将默认端口从 8080 改为其他端口（以 8081 为例）</summary>

1. 若服务正在运行，先双击 `Stop-IndexTranslate.cmd` 关闭。
2. 编辑 `scripts\run_bridge.py`，将最后一行的 `port=8080` 改为 `port=8081` 并保存。
3. 编辑 `scripts\launch.py`，将文件中所有的 `8080` 替换为 `8081` 并保存（端口探测、就绪检查与提示文本都需要保持一致）。
4. 双击 `Start-IndexTranslate.cmd` 重新启动，并在浏览器访问 `http://127.0.0.1:8081/` 确认返回 `Index-Translate Proxy Ready`。
5. 将所有客户端的 Base URL 同步修改为 `http://127.0.0.1:8081/v1`（完整地址为 `http://127.0.0.1:8081/v1/chat/completions`）；API Key、模型 ID 及关闭脚本均无需修改。

</details>

## 常见问题

<details>
<summary><strong>1. 启动时提示找不到 Python</strong></summary>

请安装 Python 3.10 或更新版本，并确保安装时启用了 Python Launcher 或勾选了 **Add python.exe to PATH**。安装完成后重新打开终端或再次双击 `Start-IndexTranslate.cmd`。

</details>

<details>
<summary><strong>2. 提示 8080 端口被占用</strong></summary>

请先区分终端的具体提示：
- `Bridge already running`：本转接服务已经在运行，无需重复启动，也不必改端口，直接在客户端使用 `http://127.0.0.1:8080/v1` 即可。
- `Port 8080 is used by another program`：`8080` 已被其他软件占用，服务未启动。可参照上文「修改默认监听端口」将其更换为空闲端口（如 `8081`），无需关闭原有程序。

</details>

<details>
<summary><strong>3. 客户端无法连接或测试失败</strong></summary>

1. 先用浏览器打开 `http://127.0.0.1:8080/`。若页面显示 `Index-Translate Proxy Ready`，说明本机转接服务运行正常（但不代表上游公网接口此时一定可用）。
2. 检查客户端协议是否为 **OpenAI Chat Completions**、Base URL 是否多写了或漏写了 `/v1`、模型 ID 拼写是否正确。
3. 若使用浏览器扩展，且浏览器弹出「允许访问本地网络」权限提示，请选择允许。
4. 确认客户端与转接服务运行在同一台电脑上（本服务默认仅绑定 `127.0.0.1`）。

</details>

<details>
<summary><strong>4. 使用转接后仍然遇到 412、429 或其他报错</strong></summary>

1. 先确认客户端的接口地址已真正切换为 `http://127.0.0.1:8080/v1`，而不是 B 站公网地址。
2. 打开 `runtime\bridge.log` 查看请求状态码与错误详情：
   - `412`：通常表示上游风控拦截了请求；
   - `429`：通常表示上游触发了请求频率限制。
3. 更换客户端里的占位 API Key 无法解决上游风控或限流问题，需要稍后重试或关注上游官方公告。

</details>

<details>
<summary><strong>5. 是否收费？是否需要配置代理？</strong></summary>

- 本项目完全免费且开源，自身不提供模型算力。上游接口目前由 B 站官方免费开放，具体可用性、限额与后续策略以官方说明为准。
- 翻译转发默认直连 B 站接口，不依赖系统代理，也不会修改你的系统代理设置。

</details>

## 项目结构

| 路径 | 用途 |
| --- | --- |
| `Start-IndexTranslate.cmd` | 双击启动入口，自动查找 Python 并拉起后台服务 |
| `Stop-IndexTranslate.cmd` | 双击关闭入口 |
| `Update-IndexTranslate.cmd` | 双击检查并更新官方脚本入口（优先 PowerShell 7） |
| `AutoStart-IndexTranslate.vbs` | 配合 Windows 启动文件夹实现登录后静默启动 |
| `scripts\call_api.py` | 上游 B 站官方 API 调用与本地转接脚本（原样引入） |
| `scripts\run_bridge.py` | 禁用系统代理并加载官方脚本启动本机服务 |
| `scripts\launch.py` | 后台无窗启动服务、检测就绪状态并记录 PID 与日志 |
| `scripts\stop_bridge.ps1` | 核对进程身份后安全停止服务 |
| `scripts\autostart.ps1` | 静默自启动辅助脚本，自动查找 Python 并记录异常 |
| `scripts\update_call_api.ps1` | 上游更新检查、AST 预检、备份回滚与来源记录同步脚本 |
| `tests\update_call_api.tests.ps1` | 更新脚本的离线自动化测试 |
| `THIRD_PARTY_NOTICES.md` | 上游脚本来源提交号与第三方许可声明 |
| `runtime\bridge.pid` | 运行时自动生成的进程号文件（已由 `.gitignore` 忽略） |
| `runtime\bridge.log` | 运行时服务访问与错误日志（已由 `.gitignore` 忽略） |
| `runtime\autostart.log` | 开机自启动失败时生成的错误日志（已由 `.gitignore` 忽略） |
| `runtime\update-backups\` | 更新官方脚本前的自动备份目录（已由 `.gitignore` 忽略） |

## 上游项目与参考

- [B 站 Index-Translate 官方仓库](https://github.com/bilibili/Index-Translate)
- [官方 API 与本地代理脚本 `call_api.py`](https://github.com/bilibili/Index-Translate/blob/main/inference/llm/call_api.py)
- [Index-Translate 官方在线体验页](https://index-translate.bilibili.com/?p=/site/translate.html&lang=zh)
- [陪读蛙（Read Frog）](https://github.com/mengxi-ream/read-frog)
- [SnowShot](https://github.com/mg-chao/snow-apps)

> 本项目为独立的第三方本地转接封装工具，与哔哩哔哩或上述示例客户端无官方隶属关系。

## 许可证

本项目基于 [Apache License 2.0](LICENSE) 开源。`scripts/call_api.py` 源自同样采用 Apache License 2.0 协议的上游 Index-Translate 项目，具体来源与提交版本见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。开源软件许可证不代表对上游在线 API 可用性或服务条款的承诺。
