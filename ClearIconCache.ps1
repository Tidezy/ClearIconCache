<#
.SYNOPSIS
    清除 Windows 图标缓存
.DESCRIPTION
    结束资源管理器 → 删除缓存文件 → 重启资源管理器。
    真正让 explorer 重新加载图标缓存，桌面/任务栏会闪烁约 3 秒。

    交互运行时（双击或在控制台窗口手动执行）会先列出将要执行的操作，
    按 Y 确认后才开始清理；加 -Force 可跳过确认。

    不需要管理员权限（只结束当前用户会话自己的 explorer 进程）。
    PowerShell 5.1+ / Windows 10/11。

.EXAMPLE
    .\ClearIconCache.ps1
    双击或在 PowerShell 窗口中直接运行（会要求按 Y 确认）。

.EXAMPLE
    .\ClearIconCache.ps1 -Force
    跳过确认，直接开始清理。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\ClearIconCache.ps1
    即使 ExecutionPolicy 设为 Restricted 也能跑（适合放到别的机器上）。

.PARAMETER Force
    跳过开头的确认提示，直接开始清理。

.NOTES
    关于 ExecutionPolicy（脚本运行策略）：
        - 默认 Win10/11 本机 .ps1 可以直接双击（策略为 RemoteSigned）
        - 如果双击后窗口一闪而过并报错 "...running scripts is disabled..."，
          说明当前用户策略禁止运行未签名脚本。按下面方法之一解决：

        方法 1（推荐，一次设置，本用户永久生效）：
            以普通身份打开 PowerShell 窗口，执行：
                Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
            然后再双击本文件即可。

        方法 2（不修改任何设置，本次绕过）：
            右键本文件 → "使用 PowerShell 运行"。
            或者在 PowerShell 窗口中执行：
                powershell -ExecutionPolicy Bypass -File .\ClearIconCache.ps1

        方法 3（彻底绕开 Windows PowerShell 5.1 的策略）：
            安装 PowerShell 7 (pwsh.exe)。它默认 RemoteSigned 且不受
            Windows PowerShell 5.1 的 GPO 策略限制。
            下载：https://github.com/PowerShell/PowerShell

    项目主页: https://github.com/Tidezy/ClearIconCache
#>

# 注意: #requires 不能移到注释帮助块前面，否则 Get-Help 将识别不到脚本帮助。
#requires -Version 5.1

param(
    [switch]$Force   # 跳过开头的确认提示（命令行/自动化用）
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = '清除 Windows 图标缓存'

Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  清除 Windows 图标缓存' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''

# 步骤 0: 确认。仅在交互控制台（双击或手动运行）提示；
# -Force 与非交互宿主（输入重定向、计划任务等）直接跳过，避免卡住自动化。
$interactive = $false
if (-not $Force) {
    try {
        $interactive = $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected
    } catch {
        $interactive = $false
    }
}

if ($interactive) {
    Write-Host '本脚本将执行以下操作:' -ForegroundColor Gray
    Write-Host '  1. 结束并重启资源管理器 explorer（桌面/任务栏闪烁约 3 秒，已打开的文件夹窗口会关闭）' -ForegroundColor Gray
    Write-Host '  2. 删除图标/缩略图缓存文件（explorer 会自动重建，不影响个人文件）' -ForegroundColor Gray
    Write-Host ''
    Write-Host -NoNewline '确认继续? [Y] 继续 / 其他键 取消: ' -ForegroundColor Yellow

    $proceed = $false
    try {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        Write-Host ''
        if ($key.Character -in 'y', 'Y') {
            $proceed = $true
        } else {
            Write-Host '已取消，未做任何更改。' -ForegroundColor Gray
        }
    } catch {
        Write-Host ''
        Write-Host '当前宿主无法读取按键输入，已取消。' -ForegroundColor Gray
    }

    if (-not $proceed) {
        Write-Host ''
        Write-Host '按任意键关闭本窗口 . . .' -ForegroundColor Gray
        try {
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        } catch { }
        exit 0
    }
}

# 只处理当前用户会话的 explorer（避免误杀其他登录用户的资源管理器）
$sessionId = (Get-Process -Id $PID).SessionId

# 步骤 1: 先尝试"优雅退出"：给任务栏窗口 Shell_TrayWnd 的属主进程发 WM_QUIT。
# 部分系统上 explorer 会整体优雅退出（不触发 AutoRestartShell，最理想）；
# 也有系统会忽略该消息或把它自动拉起——这两种情况交给步骤 2 兜底处理。
Write-Host '[1/4] 正在停止资源管理器 explorer.exe ...' -ForegroundColor Yellow
$oldExplorer = Get-Process -Name explorer -ErrorAction SilentlyContinue |
    Where-Object { $_.SessionId -eq $sessionId }
$oldId = if ($oldExplorer) { ($oldExplorer.Id -join ', ') } else { 'N/A' }
Write-Host "       当前 explorer PID: $oldId" -ForegroundColor DarkGray

$shellPid = [uint32]0
try {
    if (-not ('ClearIconCache.NativeMethods' -as [type])) {
        Add-Type -Namespace ClearIconCache -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern System.IntPtr FindWindow(string lpClassName, string lpWindowName);
[DllImport("user32.dll", SetLastError = true)]
public static extern System.Boolean PostMessage(System.IntPtr hWnd, System.UInt32 Msg, System.IntPtr wParam, System.IntPtr lParam);
[DllImport("user32.dll", SetLastError = true)]
public static extern System.UInt32 GetWindowThreadProcessId(System.IntPtr hWnd, out System.UInt32 lpdwProcessId);
'@
    }
    $trayWnd = [ClearIconCache.NativeMethods]::FindWindow('Shell_TrayWnd', $null)
    if ($trayWnd -ne [System.IntPtr]::Zero) {
        $ownerPid = [uint32]0
        [void][ClearIconCache.NativeMethods]::GetWindowThreadProcessId($trayWnd, [ref]$ownerPid)
        $shellPid = $ownerPid
        if ([ClearIconCache.NativeMethods]::PostMessage($trayWnd, [uint32]0x0012, [System.IntPtr]::Zero, [System.IntPtr]::Zero)) {
            Write-Host "       已请求优雅退出 (WM_QUIT 已发送给 shell PID: $shellPid)" -ForegroundColor DarkGray
        }
    }
} catch {
    # Win32 互操作不可用（个别受限宿主），回退为纯强杀路径
    $shellPid = [uint32]0
}
Write-Host ''

# 步骤 2: 等 explorer 退出（让锁定的文件句柄释放）。
# 阶段 1（前 1.5 秒）：只等不杀，给 WM_QUIT 优雅退出留时间；
# 阶段 2：强杀仍未退出的进程，并在剩余时间内持续压制系统自动拉起的新实例，
#         让删除开始时 explorer 尽量处于"刚启动、尚未打开缓存文件"的状态。
# AutoRestartShell=1 的机器上彻底杀干净做不到（改注册表需要管理员），
# 因此这里不把它当错误报警：第 3 步逐文件的删除结果才是唯一可靠的标准。
Write-Host '[2/4] 等待资源管理器退出 ...' -ForegroundColor Yellow
$graceEnd = (Get-Date).AddSeconds(1.5)
$forceEnd = (Get-Date).AddSeconds(4)
$running = $null
do {
    $running = Get-Process -Name explorer -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sessionId }
    if (-not $running) { break }
    if ((Get-Date) -lt $graceEnd) {
        Start-Sleep -Milliseconds 200   # 优雅退出窗口：先不杀
        continue
    }
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 200
} while ((Get-Date) -lt $forceEnd)

if ($running) {
    Write-Host '       explorer 仍在运行（AutoRestartShell 会把被结束的它自动拉起，属正常行为），' -ForegroundColor DarkGray
    Write-Host '       不再反复对抗，直接进入删除；删除结果会如实显示在下一步。' -ForegroundColor DarkGray
} else {
    Write-Host '       完成。' -ForegroundColor Green
}
Write-Host ''

# 步骤 3: 删除缓存文件（explorer 已死，文件不再被锁）
Write-Host '[3/4] 正在删除图标/缩略图缓存文件 ...' -ForegroundColor Yellow
$localAppData = $env:LOCALAPPDATA
$deleted = 0
$failed = 0

$iconCacheDb = Join-Path $localAppData 'IconCache.db'
if (Test-Path -LiteralPath $iconCacheDb) {
    try {
        Remove-Item -LiteralPath $iconCacheDb -Force -ErrorAction Stop
        $deleted++
        Write-Host "       已删除: $(Split-Path $iconCacheDb -Leaf)" -ForegroundColor DarkGray
    } catch {
        $failed++
        Write-Host "       删除失败: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$explorerDir = Join-Path $localAppData 'Microsoft\Windows\Explorer'
foreach ($pat in @('iconcache_*.db', 'thumbcache_*.db')) {
    Get-ChildItem -Path $explorerDir -Filter $pat -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            $deleted++
            Write-Host "       已删除: $($_.Name)" -ForegroundColor DarkGray
        } catch {
            $failed++
            Write-Host "       删除失败: $($_.Name)" -ForegroundColor Red
        }
    }
}

if ($failed -gt 0) {
    Write-Host "       共删除 $deleted 个文件，失败 $failed 个。" -ForegroundColor Yellow
} else {
    Write-Host "       共删除 $deleted 个文件。" -ForegroundColor Green
}
Write-Host ''

# 步骤 4: 确保 explorer 在运行。
# 若清理期间它已被系统自动拉起，桌面其实已恢复，直接跳过启动——
# 否则 Start-Process 会额外多开一个文件夹窗口。
Write-Host '[4/4] 正在重启资源管理器 ...' -ForegroundColor Yellow
$shellAlive = Get-Process -Name explorer -ErrorAction SilentlyContinue |
    Where-Object { $_.SessionId -eq $sessionId }
if ($shellAlive) {
    Write-Host '       explorer 已在运行（系统自动恢复），无需手动重启。' -ForegroundColor Green
} else {
    try {
        Start-Process -FilePath 'explorer.exe' -ErrorAction Stop
    } catch {
        Write-Host "       拉起 explorer.exe 失败: $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Seconds 2
    $shellAlive = Get-Process -Name explorer -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sessionId }
    if ($shellAlive) {
        $newIds = ($shellAlive | ForEach-Object Id) -join ', '
        Write-Host "       explorer.exe 已重启 (新 PID: $newIds)" -ForegroundColor Green
    } else {
        Write-Host '       启动失败，请按 Win+R 输入 explorer.exe 手动启动。' -ForegroundColor Red
    }
}
Write-Host ''

if ($deleted -gt 0 -and $failed -eq 0) {
    Write-Host '============================================' -ForegroundColor Green
    Write-Host '  图标缓存已清零并完全重建！' -ForegroundColor Green
    Write-Host '  桌面图标如未刷新，按 F5 即可。' -ForegroundColor Gray
    Write-Host '============================================' -ForegroundColor Green
} elseif ($deleted -eq 0 -and $failed -eq 0) {
    Write-Host '============================================' -ForegroundColor Yellow
    Write-Host '  没有找到任何缓存文件，它们可能已被清理过。' -ForegroundColor Yellow
    Write-Host '============================================' -ForegroundColor Yellow
} else {
    Write-Host '============================================' -ForegroundColor Red
    Write-Host "  有 $failed 个缓存文件删除失败，重建可能不完整！" -ForegroundColor Red
    Write-Host '  提示: 重启电脑（让 explorer 彻底释放文件）后重试本脚本。' -ForegroundColor Yellow
    Write-Host '============================================' -ForegroundColor Red
}
Write-Host ''
Write-Host '按任意键关闭本窗口 . . .' -ForegroundColor Gray
try {
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
} catch {
    # 非交互宿主（ISE / 重定向输入等）无需暂停，直接结束
}
