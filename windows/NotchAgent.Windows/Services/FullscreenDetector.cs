using System.Runtime.InteropServices;

namespace NotchAgent.Windows.Services;

/// A notch-like always-on-top bar must get out of the way of games, video
/// players and presentations — the same courtesy Discord/NVIDIA overlays
/// give. Windows-only; every call is gated behind OperatingSystem.IsWindows()
/// so the P/Invoke stubs are never touched when running/testing on macOS.
public static class FullscreenDetector
{
    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo
    {
        public uint Size;
        public Rect Monitor;
        public Rect WorkArea;
        public uint Flags;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MonitorInfo info);

    private const uint MonitorDefaultToNearest = 2;

    /// True when the current foreground window covers its entire monitor.
    public static bool IsForegroundFullscreen()
    {
        if (!OperatingSystem.IsWindows()) return false;
        try
        {
            var hwnd = GetForegroundWindow();
            if (hwnd == IntPtr.Zero || !GetWindowRect(hwnd, out var winRect)) return false;

            var monitor = MonitorFromWindow(hwnd, MonitorDefaultToNearest);
            var info = new MonitorInfo { Size = (uint)Marshal.SizeOf<MonitorInfo>() };
            if (!GetMonitorInfo(monitor, ref info)) return false;

            return winRect.Left <= info.Monitor.Left && winRect.Top <= info.Monitor.Top
                && winRect.Right >= info.Monitor.Right && winRect.Bottom >= info.Monitor.Bottom;
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException)
        {
            return false;
        }
    }
}
