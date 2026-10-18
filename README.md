# ClearIconCache

一键清除并重建 Windows 图标 / 缩略图缓存。桌面图标错乱、显示成白纸、缩略图不刷新时，跑一次即可。

## ✨ 特点

- **无需管理员权限** —— 只结束当前用户会话自己的 explorer 进程，不碰其他登录用户
- **优先优雅退出** —— 先向任务栏窗口发送 `WM_QUIT` 请求 explorer 自行退出；对开启了 `AutoRestartShell` 的机器会如实说明系统行为，不会误报错误
- **逐文件结果汇报** —— 每个缓存文件的删除结果都会单独显示；结尾横幅按实际结果变色（绿色 = 全部成功；红色 = 有失败并给出处理建议）
- **删除范围明确** —— 只处理 `IconCache.db` 与 `iconcache_*.db` / `thumbcache_*.db`，不触碰其他文件
- **中文输出不乱码** —— 脚本使用 UTF-8 带 BOM 保存，Windows PowerShell 5.1 下显示正常

## 🚀 使用方法

双击运行本脚本；或者在 PowerShell 窗口中执行：

```powershell
.\ClearIconCache.ps1
```

如果提示 *running scripts is disabled*，说明当前用户执行策略禁止运行脚本，任选一种方式解决：

| 方式 | 操作 |
| --- | --- |
| 一次设置，永久生效（推荐） | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| 本次绕过，不改设置 | `powershell -ExecutionPolicy Bypass -File .\ClearIconCache.ps1` |
| 右键菜单 | 右键文件 → "使用 PowerShell 运行" |

运行期间桌面、任务栏会消失约 3 秒后自动恢复，属正常现象。

## 📋 运行流程

| 步骤 | 说明 |
| --- | --- |
| 1. 停止 explorer | 先发 `WM_QUIT` 优雅退出请求，失败则强杀兜底 |
| 2. 等待退出 | 轮询检测进程退出，等待文件句柄释放 |
| 3. 删除缓存 | `%LOCALAPPDATA%\IconCache.db` 及 `%LOCALAPPDATA%\Microsoft\Windows\Explorer\` 下的 `iconcache_*.db` / `thumbcache_*.db` |
| 4. 重启 explorer | 若系统已自动拉起则跳过，避免多开文件夹窗口 |

## ❓ 常见问题

**Q：为什么出现 "explorer 仍在运行（AutoRestartShell…）"？**

部分 Windows 默认开启 `AutoRestartShell`：explorer 被结束后会被系统立即自动拉起。这是系统策略（修改它需要管理员权限），脚本不会反复对抗。实测此时新拉起的 explorer 不会锁住缓存文件，删除照常完成——脚本以第 3 步的逐文件删除结果为准。

**Q：为什么没有删除 `IconCache.db`？**

现代 Windows 对该文件采取按需重建策略，删除过后通常不会立即重建，甚至长期不存在。找不到该文件不影响清理效果。

**Q：清完后图标还是旧的？**

按 F5 刷新桌面。个别第三方软件使用自身的图标缓存，重启后才会更新。

## 📄 许可证

[MIT](LICENSE)
