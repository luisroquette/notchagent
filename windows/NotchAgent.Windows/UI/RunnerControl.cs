using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Threading;

namespace NotchAgent.Windows.UI;

/// Chrome-dino homage wired to the real session gauge — a port of
/// NotchRunnerView.swift. Obstacles ARE the tokens running out: the world
/// speeds up and packs tighter as the window drains, and at 0% the run ends
/// in an 8-bit GAME OVER until the window resets.
public sealed class RunnerControl : Control
{
    private static readonly int[][] GaitA =
    {
        new[] { 0, 1, 1, 0, 0, 1, 1, 0 },
        new[] { 1, 1, 1, 1, 1, 1, 1, 1 },
        new[] { 1, 2, 1, 1, 1, 2, 1, 1 },
        new[] { 1, 1, 1, 1, 1, 1, 1, 1 },
        new[] { 0, 1, 0, 0, 1, 0, 0, 0 },
    };
    private static readonly int[][] GaitB =
    {
        new[] { 0, 1, 1, 0, 0, 1, 1, 0 },
        new[] { 1, 1, 1, 1, 1, 1, 1, 1 },
        new[] { 1, 2, 1, 1, 1, 2, 1, 1 },
        new[] { 1, 1, 1, 1, 1, 1, 1, 1 },
        new[] { 0, 0, 1, 0, 0, 0, 1, 0 },
    };
    private static readonly int[][] Dead =
    {
        new[] { 0, 0, 0, 0, 0, 0, 0, 0 },
        new[] { 0, 1, 0, 0, 1, 0, 0, 0 },
        new[] { 1, 1, 1, 1, 1, 1, 1, 1 },
        new[] { 1, 2, 1, 1, 1, 2, 1, 1 },
        new[] { 1, 1, 1, 1, 1, 1, 1, 1 },
    };

    public static readonly StyledProperty<double> UsedPercentProperty =
        AvaloniaProperty.Register<RunnerControl, double>(nameof(UsedPercent));
    public static readonly StyledProperty<bool> IsGameOverProperty =
        AvaloniaProperty.Register<RunnerControl, bool>(nameof(IsGameOver));
    public static readonly StyledProperty<DateTimeOffset?> ResetsAtProperty =
        AvaloniaProperty.Register<RunnerControl, DateTimeOffset?>(nameof(ResetsAt));
    public static readonly StyledProperty<Color> ObstacleTintProperty =
        AvaloniaProperty.Register<RunnerControl, Color>(nameof(ObstacleTint), AppTheme.CoralDim);
    public static readonly StyledProperty<Color> TintProperty =
        AvaloniaProperty.Register<RunnerControl, Color>(nameof(Tint), AppTheme.Coral);

    public double UsedPercent { get => GetValue(UsedPercentProperty); set => SetValue(UsedPercentProperty, value); }
    public bool IsGameOver { get => GetValue(IsGameOverProperty); set => SetValue(IsGameOverProperty, value); }
    public DateTimeOffset? ResetsAt { get => GetValue(ResetsAtProperty); set => SetValue(ResetsAtProperty, value); }
    public Color ObstacleTint { get => GetValue(ObstacleTintProperty); set => SetValue(ObstacleTintProperty, value); }
    public Color Tint { get => GetValue(TintProperty); set => SetValue(TintProperty, value); }

    private const double RunnerX = 12;
    private const double BaseSpeed = 46;
    private static readonly double[] BaseSpacing = { 170, 240, 205, 290 };
    private readonly DispatcherTimer _timer;
    private readonly DateTime _epoch = DateTime.UtcNow;

    public RunnerControl()
    {
        ClipToBounds = true;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1000.0 / 20) };
        _timer.Tick += (_, _) => InvalidateVisual();
        _timer.Start();
    }

    private double Difficulty => Math.Min(Math.Max(UsedPercent, 0), 100) / 100;
    private double Speed => BaseSpeed + Difficulty * 66;
    private double SpacingScale => 1 - Difficulty * 0.52;

    public override void Render(DrawingContext context)
    {
        var time = (DateTime.UtcNow - _epoch).TotalSeconds;
        var size = Bounds.Size;
        if (IsGameOver) DrawGameOver(context, size, time);
        else DrawRun(context, size, time);
    }

    private void DrawRun(DrawingContext context, Size size, double time)
    {
        double groundY = size.Height - 1.5;
        DrawGround(context, size, groundY, time * Speed);

        double loop = (size.Width + 60) * SpacingScale + size.Width * (1 - SpacingScale);
        double nextObstacleDistance = double.MaxValue;
        var offsets = ObstacleOffsets();
        for (int i = 0; i < offsets.Length; i++)
        {
            double x = loop - (time * Speed + offsets[i] * SpacingScale) % loop;
            DrawObstacle(context, x, groundY, i);
            double distance = x - RunnerX;
            if (distance > -6 && distance < nextObstacleDistance) nextObstacleDistance = distance;
        }

        double jumpHeight = 0;
        if (nextObstacleDistance < 38)
        {
            double progress = 1 - Math.Max(nextObstacleDistance, -6) / 38;
            jumpHeight = Math.Sin(Math.Min(progress, 1) * Math.PI) * 13;
        }

        double gaitFps = 8.0 + Difficulty * 6;
        var frame = (int)(time * gaitFps) % 2 == 0 ? GaitA : GaitB;
        var grid = jumpHeight > 1 ? GaitA : frame;
        DrawSprite(context, grid, RunnerX, groundY - jumpHeight, deadEyes: false);
    }

    private void DrawGameOver(DrawingContext context, Size size, double time)
    {
        double groundY = size.Height - 1.5;
        var pen = new Pen(new SolidColorBrush(AppTheme.Danger, 0.4), 1);
        context.DrawLine(pen, new Point(0, groundY), new Point(size.Width, groundY));

        DrawSprite(context, Dead, RunnerX, groundY, deadEyes: true);

        bool blinkOn = (int)(time * 1.6) % 2 == 0;
        bool narrow = size.Width < 420;
        double anchorX = narrow ? size.Width - 34 : size.Width / 2;
        var typeface = new Typeface("Consolas");

        if (narrow)
        {
            if (blinkOn)
            {
                DrawText(context, "GAME OVER", anchorX, groundY - 20, 9, AppTheme.Danger, typeface);
            }
            else if (ResetsAt is { } reset)
            {
                DrawText(context, Services.Format.Time(reset), anchorX, groundY - 20, 9, AppTheme.TextFaint, typeface);
            }
        }
        else
        {
            if (blinkOn) DrawText(context, "GAME OVER", anchorX, groundY - 22, 13, AppTheme.Danger, typeface, center: true);
            if (ResetsAt is { } reset)
            {
                DrawText(context, $"NEW RUN {Services.Format.Time(reset)}", anchorX, groundY - 8, 8, AppTheme.TextFaint, typeface, center: true);
            }
        }
    }

    private void DrawGround(DrawingContext context, Size size, double groundY, double scroll)
    {
        var pen = new Pen(new SolidColorBrush(Tint, 0.25), 1);
        double dashX = -(scroll % 12);
        while (dashX < size.Width)
        {
            context.DrawLine(pen, new Point(Math.Max(dashX, 0), groundY), new Point(Math.Min(dashX + 6, size.Width), groundY));
            dashX += 12;
        }
    }

    private void DrawSprite(DrawingContext context, int[][] grid, double x, double groundY, bool deadEyes)
    {
        const double pixel = 2.5;
        double spriteHeight = grid.Length * pixel;
        double originY = groundY - spriteHeight;
        var bodyBrush = new SolidColorBrush(Tint);
        var eyeBrush = new SolidColorBrush(Colors.Black, 0.9);

        for (int row = 0; row < grid.Length; row++)
        {
            for (int col = 0; col < grid[row].Length; col++)
            {
                int cell = grid[row][col];
                if (cell == 0) continue;
                var rect = new Rect(x + col * pixel, originY + row * pixel, pixel * 0.9, pixel * 0.9);
                if (cell == 2 && deadEyes)
                {
                    var pen = new Pen(eyeBrush, 0.8);
                    context.DrawLine(pen, rect.TopLeft, rect.BottomRight);
                    context.DrawLine(pen, rect.TopRight, rect.BottomLeft);
                }
                else
                {
                    context.FillRectangle(cell == 2 ? eyeBrush : bodyBrush, rect);
                }
            }
        }
    }

    private void DrawObstacle(DrawingContext context, double x, double groundY, int variant)
    {
        const double pixel = 2.5;
        int[][] columns = variant % 2 == 0
            ? new[] { new[] { 0, 1, 0 }, new[] { 1, 1, 1 }, new[] { 0, 1, 0 }, new[] { 0, 1, 0 } }
            : new[] { new[] { 1, 1 }, new[] { 1, 1 }, new[] { 1, 1 } };
        double height = columns.Length * pixel;
        var brush = new SolidColorBrush(ObstacleTint);
        for (int row = 0; row < columns.Length; row++)
        {
            for (int col = 0; col < columns[row].Length; col++)
            {
                if (columns[row][col] != 1) continue;
                var rect = new Rect(x + col * pixel, groundY - height + row * pixel, pixel * 0.9, pixel * 0.9);
                context.FillRectangle(brush, rect);
            }
        }
    }

    private double[] ObstacleOffsets()
    {
        var offsets = new double[BaseSpacing.Length];
        double acc = 0;
        for (int i = 0; i < BaseSpacing.Length; i++)
        {
            acc += BaseSpacing[i];
            offsets[i] = acc;
        }
        return offsets;
    }

    private void DrawText(DrawingContext context, string text, double x, double y, double size, Color color, Typeface typeface, bool center = false)
    {
        var formatted = new FormattedText(text, System.Globalization.CultureInfo.InvariantCulture,
            FlowDirection.LeftToRight, typeface, size, new SolidColorBrush(color));
        var origin = center ? new Point(x - formatted.Width / 2, y) : new Point(x - formatted.Width, y);
        context.DrawText(formatted, origin);
    }
}
