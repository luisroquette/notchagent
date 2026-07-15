using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;

namespace NotchAgent.Windows.UI;

/// Generates the tray icon bitmap procedurally (no image assets needed) —
/// a black rounded tile with a state-colored inner square, echoing the
/// Mac app's coral-on-black chassis.
public static class TrayIconFactory
{
    public static WindowIcon Create(Color stateColor)
    {
        var inner = new Border
        {
            Width = 20,
            Height = 20,
            Background = new SolidColorBrush(stateColor),
            CornerRadius = new CornerRadius(5),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var outer = new Border
        {
            Width = 32,
            Height = 32,
            Background = new SolidColorBrush(Colors.Black),
            CornerRadius = new CornerRadius(8),
            Child = inner,
        };
        outer.Measure(new Size(32, 32));
        outer.Arrange(new Rect(0, 0, 32, 32));

        var bitmap = new RenderTargetBitmap(new PixelSize(32, 32), new Vector(96, 96));
        bitmap.Render(outer);

        using var stream = new MemoryStream();
        bitmap.Save(stream);
        stream.Position = 0;
        return new WindowIcon(stream);
    }
}
