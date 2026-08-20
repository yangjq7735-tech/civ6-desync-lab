[CmdletBinding()]
param(
    [int]$X,
    [int]$Y,
    [switch]$Enter,
    [string[]]$ProcessName = @('CivilizationVI_DX12', 'CivilizationVI')
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class Civ6InteractiveInput
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public uint type; public InputUnion U; }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT
    {
        public int dx; public int dy; public uint mouseData; public uint dwFlags;
        public uint time; public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT
    {
        public ushort wVk; public ushort wScan; public uint dwFlags;
        public uint time; public UIntPtr dwExtraInfo;
    }

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint source, uint target, bool attach);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr SetActiveWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr SetFocus(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, INPUT[] inputs, int size);

    static IntPtr FindWindow(uint processId)
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr hWnd, IntPtr unused) {
            uint candidate;
            GetWindowThreadProcessId(hWnd, out candidate);
            if (candidate == processId && IsWindowVisible(hWnd)) {
                found = hWnd;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static uint ClickAndEnter(uint processId, int x, int y, bool pressEnter)
    {
        IntPtr hWnd = FindWindow(processId);
        if (hWnd == IntPtr.Zero) return 0;

        uint ignored;
        uint currentThread = GetCurrentThreadId();
        uint targetThread = GetWindowThreadProcessId(hWnd, out ignored);
        uint foregroundThread = GetWindowThreadProcessId(GetForegroundWindow(), out ignored);
        AttachThreadInput(currentThread, foregroundThread, true);
        AttachThreadInput(currentThread, targetThread, true);
        ShowWindow(hWnd, 9);
        BringWindowToTop(hWnd);
        SetForegroundWindow(hWnd);
        SetActiveWindow(hWnd);
        SetFocus(hWnd);
        SetCursorPos(x, y);

        INPUT[] mouse = new INPUT[2];
        mouse[0].type = 0; mouse[0].U.mi.dwFlags = 0x0002;
        mouse[1].type = 0; mouse[1].U.mi.dwFlags = 0x0004;
        uint sent = SendInput(2, mouse, Marshal.SizeOf(typeof(INPUT)));

        if (pressEnter) {
            System.Threading.Thread.Sleep(500);
            INPUT[] keys = new INPUT[2];
            keys[0].type = 1; keys[0].U.ki.wVk = 0x0D;
            keys[1].type = 1; keys[1].U.ki.wVk = 0x0D; keys[1].U.ki.dwFlags = 0x0002;
            sent += SendInput(2, keys, Marshal.SizeOf(typeof(INPUT)));
        }
        AttachThreadInput(currentThread, targetThread, false);
        AttachThreadInput(currentThread, foregroundThread, false);
        return sent;
    }
}
'@

$process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $process) {
    throw "No matching Civ VI process is running: $($ProcessName -join ', ')"
}

$sent = [Civ6InteractiveInput]::ClickAndEnter([uint32]$process.Id, $X, $Y, $Enter.IsPresent)
if ($sent -eq 0) {
    throw "No visible Civ VI window was found for process $($process.Id)."
}

[ordered]@{
    status    = 'sent'
    processId = $process.Id
    x         = $X
    y         = $Y
    events    = $sent
} | ConvertTo-Json
