using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;

namespace NotchAgent.Windows.UI;

/// Chunky block meter, the stick's signature gauge — a direct port of
/// SegmentedMeter.swift. Filled blocks take the state color; empty blocks
/// stay as faint sockets.
public sealed class SegmentedMeter : Control
{
    public static readonly StyledProperty<double> PercentProperty =
        AvaloniaProperty.Register<SegmentedMeter, double>(nameof(Percent));
    public static readonly StyledProperty<IBrush> TintProperty =
        AvaloniaProperty.Register<SegmentedMeter, IBrush>(nameof(Tint), AppTheme.Brush(AppTheme.Coral));
    public static readonly StyledProperty<int> SegmentsProperty =
        AvaloniaProperty.Register<SegmentedMeter, int>(nameof(Segments), 12);

    public double Percent { get => GetValue(PercentProperty); set => SetValue(PercentProperty, value); }
    public IBrush Tint { get => GetValue(TintProperty); set => SetValue(TintProperty, value); }
    public int Segments { get => GetValue(SegmentsProperty); set => SetValue(SegmentsProperty, value); }

    static SegmentedMeter()
    {
        AffectsRender<SegmentedMeter>(PercentProperty, TintProperty, SegmentsProperty);
    }

    public override void Render(DrawingContext context)
    {
        var segments = Math.Max(1, Segments);
        var clamped = Math.Min(Math.Max(Percent, 0), 100);
        var filled = clamped > 0 ? Math.Max(1, (int)Math.Round(clamped / 100 * segments)) : 0;

        const double spacing = 2;
        var totalSpacing = spacing * (segments - 1);
        var segmentWidth = (Bounds.Width - totalSpacing) / segments;
        var socket = AppTheme.Brush(AppTheme.Socket);

        for (int i = 0; i < segments; i++)
        {
            var x = i * (segmentWidth + spacing);
            var rect = new Rect(x, 0, segmentWidth, Bounds.Height);
            var brush = i < filled ? Tint : socket;
            context.DrawRectangle(brush, null, rect, 1.5, 1.5);
        }
    }
}
