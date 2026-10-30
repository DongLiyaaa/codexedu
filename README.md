# codexedu · Codex Island

一个轻量的 macOS 原生 Codex 额度浮窗。将套餐、剩余额度和重置倒计时放在屏幕顶部的一条小胶囊中，无需打开终端或网页查看。

> 非 OpenAI 官方产品，与 OpenAI 无隶属关系。当前为早期版本，依赖官方客户端使用的后端接口，接口及授权政策可能变化。

## v.0.0.1 跨平台打包

版本标签为 `v.0.0.1`，系统内部版本为 `0.0.1`。macOS 保留 SwiftUI 原生实现；`desktop/` 是新增的 Windows/Linux Tauri 2 客户端。

- macOS：`bash script/package_macos.sh` 生成当前架构 DMG；尚未 Developer ID 签名或公证。
- Windows/Linux：安装 Node.js、Rust 与 Tauri 系统依赖，在 `desktop/` 运行 `npm ci && npm run build`。
- GitHub Actions 的 `Build v.0.0.1 packages` 工作流分别在原生 runner 上构建；构建成功不等于已经完成安装和登录的实机验收。
- Windows/Linux 暂无系统托盘入口，通过任务栏管理窗口、右键浮窗调整主题。玻璃主题为视觉近似，不提供 Apple Liquid Glass。
- Windows/Linux 登录文件位于 Tauri 的当前用户 `app_local_data_dir`，不会与 macOS 或 Codex CLI 共用。Unix 文件权限为 0600；Windows 使用当前用户应用数据目录的继承 ACL，凭据仍为明文。
- 三端安装包均处于早期测试阶段，不保证跨系统效果完全一致。

## 功能

- **固定单行浮窗**：330 × 28 pt，显示套餐、主要额度窗口的剩余百分比、距重置时间与刷新按钮。
- **九种主题**：苹果玻璃、暗色、白色、赛博朋克、GTA6、Gemini、OpenAI、Claude、DeepSeek；macOS 菜单栏或右键浮窗可切换并保存偏好。
- **主动授权登录**：由用户在官方页面完成设备授权，不读取浏览器 Cookie 或其他 Codex 客户端的登录文件。
- **保持登录**：使用应用独立的本地凭据文件，启动时恢复会话，令牌到期时尝试自动续期。
- **自动刷新**：正常每 120 秒查询一次，失败后等待 15 分钟；可手动刷新。
- **低干扰**：无 Dock 图标，无额度通知，无演示数据，不抢键盘焦点；支持拖动、隐藏及恢复顶部居中。

## 系统要求

- macOS 14 或更高版本。
- Swift 5.9+；建议使用当前版本的 Xcode 或 Command Line Tools。
- 支持 Codex 的 ChatGPT 账号及可访问官方服务的网络。
- macOS 26 使用原生 Liquid Glass；较旧系统使用系统材质降级显示。

无需安装 Codex CLI、Node.js、Docker 或数据库。

## 构建与启动

```bash
git clone https://github.com/DongLiyaaa/codexedu.git
cd codexedu
./script/build_and_run.sh --verify
```

脚本会编译、生成 `dist/CodexIsland.app`、使用本地 ad-hoc 签名并启动应用。重新运行只会停止本项目生成的应用进程，不会停止其他 Codex 客户端。

也可以只编译：

```bash
swift build --product CodexIsland
```

GUI 应用请通过生成的 `.app` 启动。当前未提供 Developer ID 签名、公证或自动更新，不建议将本地构建直接当作已公证的分发包。

## 使用

1. 点击浮窗右侧的 **登录**，或菜单栏中的 **登录授权**。
2. 应用显示设备授权码并打开官方授权页面；点击授权码可复制，由你本人完成授权。
3. 登录成功后，浮窗显示真实额度。授权码与令牌均不应分享。
4. 点击最右侧刷新按钮更新数据；将鼠标停留在倒计时上可查看准确重置时间。
5. 菜单栏提供主题、隐藏、居中、登录与退出等操作。

**退出软件**会保留登录文件；**退出本应用账号**会删除该文件并清空内存会话，不会退出其他客户端或撤销其他会话。

## 额度与套餐说明

- 剩余额度按接口的已用百分比换算，不估算还能发送多少条消息。
- 当前单行显示主要额度窗口，不合并多个窗口计算所谓“总额度”。
- 重置倒计时归零后等待服务端确认，不自行将额度恢复为 100%。
- 百分比后的 `*` 表示数据过期；悬停可查看当前状态。
- 显示名称映射为 `pro → Pro 20x`、`prolite → Pro 5x`、`promax → Pro 50x`、`plus → Plus`。倍率是应用侧的标签映射，并非额度接口直接返回的倍率数值；其他套餐保留其名称。

## 隐私与安全

应用直接访问官方服务：

- `https://auth.openai.com`：设备授权及令牌刷新。
- `https://chatgpt.com/backend-api/wham/usage`：只读额度查询。

应用不提供自己的云端后台，不发送模型请求，不充值，也不消耗额度重置权益。鉴权请求拒绝重定向，HTTP 会话不持久化 Cookie 或缓存。

### 本地凭据

凭据保存于当前用户的应用支持目录：

```text
~/Library/Application Support/CodexIsland/session.json
```

这里的 `~` 表示使用者自己的主目录，不是某台开发机器的固定路径。

- 目录权限 `0700`，文件权限 `0600`。
- 更新使用同目录临时文件与原子替换。
- **凭据以明文保存，不是加密文件，也不使用 macOS 钥匙串。** 同一用户权限的程序、备份软件或已入侵的系统仍可能访问它。
- 不要将凭据、授权码、HTTP 鉴权头或完整响应上传到 GitHub、日志平台或问题反馈中。
- 仓库忽略登录文件、环境文件、私钥、构建产物和常见本地开发文件。

公共 OAuth client ID 是协议所需的公开应用标识，不是用户令牌或 client secret。该登录流程沿用官方 Codex 客户端协议，第三方使用的兼容性、账号策略与未来可用性不作保证。

## 开发与测试

```bash
# 无 XCTest 依赖的离线逻辑检查
swift run QuotaCheck

# 在提供 XCTest 的开发环境中运行
swift test
```

仅安装 Command Line Tools 的部分环境可能报 `no such module 'XCTest'`；可先运行独立检查程序，或安装包含 XCTest 的完整 Xcode 开发环境。

```text
Sources/
  CodexIsland/       浮窗、主题、授权与凭据存储
  QuotaCore/         额度模型及 HTTP 客户端
  QuotaCheck/        独立离线检查
Tests/              XCTest 测试
script/             构建、打包与启动脚本
```

## 当前限制

- 设备授权、令牌续期、重启恢复登录仍需在不同账号与网络环境下充分验收。
- 多显示器、全屏、睡眠恢复与五种主题的跨系统视觉效果仍需完整测试。
- 仅监控一个授权账号；暂无多账号管理、开机启动或完整设置窗口。
- 当前 UI 不同时展示所有附加额度窗口。
- 使用的是官方客户端后端接口，而不是承诺长期稳定的公开开发者 API。

反馈问题时，请只提供系统版本、复现步骤和脱敏后的错误信息。

## 参考

- [OpenAI Codex 设备授权实现](https://github.com/openai/codex/blob/main/codex-rs/login/src/device_code_auth.rs)
- [OpenAI Codex 额度接口实现](https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/client/rate_limit_resets.rs)

## 许可证

本项目采用 [MIT License](LICENSE)。项目名称与主题名称仅用于描述；相关第三方商标归各自所有者所有。
