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
