# Index Translate Bridge

在 Windows 上将陪读蛙、SnowShot 等支持 OpenAI 兼容接口的工具，接入哔哩哔哩 Index-Translate 翻译服务。

本项目使用 [Index-Translate 官方提供的 `call_api.py`](https://github.com/bilibili/Index-Translate/blob/main/inference/llm/call_api.py) 作为转接核心，补充后台启动和关闭脚本。无需在本地下载或运行模型，无需安装额外 Python 包。

## 工作原理

```text
陪读蛙 / SnowShot / 其他客户端
              ↓
本机转接服务 http://127.0.0.1:8080/v1
              ↓
B 站 Index-Translate 官方 API
```

部分浏览器扩展直接请求 B 站 API 时，可能收到 `412` 安全风控错误。本项目让客户端先访问本机，再由官方脚本向 B 站发起请求，避免将浏览器扩展的来源信息直接传给上游。

这能解决部分直接接入时的兼容问题，但不保证解决所有风控或网络故障。实际翻译在 B 站服务器完成，需要联网，原文会发送至官方服务。

## 运行要求

- Windows 10 / 11。
- Python 3.10 或更新版本，推荐使用 [Python 官网](https://www.python.org/downloads/windows/)提供的安装程序。
- 安装时启用 Python Launcher，或勾选 **Add python.exe to PATH**。
- 本机 `8080` 端口可用，网络能够直连 `index-translate.bilibili.com`。

可在终端执行 `py -3 --version` 或 `python --version`，确认 Python 已安装。

当前启动、关闭脚本面向 Windows，暂未提供 macOS / Linux 的配套管理脚本。

## 快速开始

### 1. 下载

在 GitHub 仓库页面选择 **Code → Download ZIP**，解压到本地文件夹。请先解压，再运行其中的脚本。

### 2. 启动服务

双击 `Start-IndexTranslate.cmd`。

看到以下提示，表示启动成功：

```text
Bridge started. You may close this window.
Base URL: http://127.0.0.1:8080/v1
```

启动后可以关闭命令窗口，服务会继续在后台运行。再次启动时，如果服务已在运行，会提示 `Bridge already running`。

也可以在项目目录的终端中执行：

```powershell
py -3 -I launch.py
```

如果安装的 Python 没有 `py` 命令，可改用 `python -I launch.py`。

### 3. 配置客户端

在需要接入的工具中填写：

| 配置项 | 内容 |
| --- | --- |
| 名称 | 自行命名，例如 `Index 翻译` |
| 接口类型 | OpenAI 兼容 / Chat Completions |
| Base URL / API 地址 | `http://127.0.0.1:8080/v1` |
| API Key | `index` |
| 模型 ID | `Index-Translate-35B-A3B` |

`index` 是供客户端使用的占位文字，不是需要申请的密钥。本机转接服务不验证密钥，也不会把客户端填写的密钥转发给上游。

上表地址适用于 **Base URL** 字段，客户端会自动补上 `/chat/completions`。如果软件明确要求填写完整请求地址，则使用：

```text
http://127.0.0.1:8080/v1/chat/completions
```

### 4. 关闭服务

双击 `Stop-IndexTranslate.cmd`，出现 `Bridge stopped` 表示已关闭。重复关闭会提示服务已停止。

关闭脚本会根据 PID 文件核对 Python 进程和本文件夹中的 `run_bridge.py` 路径，再停止对应进程。

关闭后，使用此接口的翻译功能暂停。再次双击启动脚本即可恢复，无需重新配置客户端。电脑重启后也需要重新启动服务；本项目不设置开机自启。

## 陪读蛙配置

1. 打开设置，进入 **API 提供商 → 添加提供商**。
2. 选择 **自定义 Chat Complete**，或使用 Chat Completions 协议的 OpenAI 兼容选项。
3. 按上表填写 Base URL、API Key 和模型 ID。
4. 测试连接。
5. 在 **功能提供商** 中，为网页翻译、划词翻译等功能选择刚添加的提供商。
6. 将翻译目标语言设为需要的语言，例如简体中文。

菜单名称可能随版本变化。模型不在下拉列表时，可以手动填写模型 ID。

## SnowShot 配置

1. 在设置中找到 **自定义模型 → 添加模型**。旧版入口可能是 **设置 → 功能设置 → AI 对话 → 添加 API 配置**。
2. 按上表填写接口信息，若有“推理支持 / 思考模式”选项，先关闭。
3. 在 **翻译** 设置中，将翻译服务切换为刚添加的模型，并设置目标语言。
4. 使用截图翻译或选中文本翻译功能。

对于采用插件管理的版本，需要安装 **翻译、文本识别、AI 对话** 插件。常规截图翻译会先识别图片中的文字，再调用模型翻译。

## 常见问题

### 提示找不到 Python

安装 Python 3.10 或更新版本，并启用 Python Launcher 或将 Python 加入 PATH。安装完成后，重新打开终端或再次运行启动脚本。

### 提示 8080 端口被占用

先区分两种提示：

- `Bridge already running`：表示转接服务已经启动，无需重复启动，也无需改端口。陪读蛙、SnowShot 中的 Base URL 仍填写 `http://127.0.0.1:8080/v1`。
- `Port 8080 is used by another program`：表示 `8080` 端口被其他程序占用，转接服务没有启动。可以给转接服务换一个空闲端口，例如 `8081`，不必关闭其他程序。

**修改端口的方法（以 8081 为例）：**

1. 如果本项目的转接服务正在运行，先双击 `Stop-IndexTranslate.cmd` 关闭它。
2. 用记事本或代码编辑器打开 `run_bridge.py`，将最后一行的 `port=8080` 改为 `port=8081`，保存。
3. 打开 `launch.py`，将文件中所有的 `8080` 替换为 `8081`，保存。启动脚本中的检测地址、端口检查和启动提示都需要使用新端口，因此两个文件必须一起修改。
4. 双击 `Start-IndexTranslate.cmd` 重新启动，并把陪读蛙、SnowShot 等客户端中的 Base URL 改为：

   ```text
   http://127.0.0.1:8081/v1
   ```

如果客户端要求完整请求地址，则改为 `http://127.0.0.1:8081/v1/chat/completions`。API Key 和模型 ID 不变，关闭脚本无需修改。

修改后，可用浏览器访问 `http://127.0.0.1:8081/` 检查服务。本文其他示例仍以默认端口 `8080` 为例，实际使用时请换成你设置的端口。如果 `8081` 也被占用，可选择其他空闲端口（范围为 `1–65535`）。

### 客户端无法连接

先启动服务，再通过浏览器访问：

```text
http://127.0.0.1:8080/
```

显示 `Index-Translate Proxy Ready` 说明本机服务已启动，但不代表上游 API 一定可用。

如果本机服务正常，检查客户端是否选择了 Chat Completions 协议、地址是否填写正确，以及模型 ID 是否为 `Index-Translate-35B-A3B`。浏览器或扩展若提示本地网络访问权限，需要允许访问本机。

### 仍然出现 412 或其他上游错误

先确认客户端已经改用 `http://127.0.0.1:8080/v1`，而不是 B 站公网地址。

若转接后仍出现错误，查看 `bridge.log` 中的状态码和客户端报错。`412` 通常表示上游风控拒绝请求，`429` 通常表示请求受到限流；换占位密钥无法解决这些问题。上游服务不可用或访问规则调整时，需要等待恢复或查看官方说明。

### 是否收费？是否需要代理？

本项目不收费、不提供模型算力。上游 API 目前由 B 站官方免费开放，具体可用性、额度及后续政策以官方说明为准。

本机服务只监听 `127.0.0.1`，上游请求采用直连，不使用系统代理，也不修改系统代理设置。客户端与转接服务应运行在同一台电脑上。

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `call_api.py` | 来自 B 站官方项目的 API 调用及本地转接脚本 |
| `run_bridge.py` | 加载官方脚本，以直连方式启动本机服务 |
| `launch.py` | 后台启动服务，记录 PID 和运行日志 |
| `Start-IndexTranslate.cmd` | 双击启动入口，自动查找 Python |
| `stop_bridge.ps1` | 核对进程身份并关闭服务 |
| `Stop-IndexTranslate.cmd` | 双击关闭入口 |
| `bridge.log` | 运行时生成的日志 |
| `bridge.pid` | 运行时生成的进程编号文件 |

上传 GitHub 时，运行产生的 `bridge.log`、`bridge.pid` 和 `__pycache__/` 不需要提交。

## 上游项目与参考

- [B 站 Index-Translate 项目](https://github.com/bilibili/Index-Translate)
- [官方 API 脚本](https://github.com/bilibili/Index-Translate/blob/main/inference/llm/call_api.py)
- [官方翻译体验网页](https://index-translate.bilibili.com/?p=/site/translate.html&lang=zh)
- [陪读蛙](https://github.com/mengxi-ream/read-frog)
- [SnowShot](https://github.com/mg-chao/snow-apps)

本项目是独立的本地转接工具，非 B 站、陪读蛙或 SnowShot 官方产品。

## 许可证

本项目采用 [Apache License 2.0](LICENSE)。`call_api.py` 来自采用相同许可证的上游 Index-Translate 项目，来源说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。软件许可证不代表上游 API 的服务承诺。
