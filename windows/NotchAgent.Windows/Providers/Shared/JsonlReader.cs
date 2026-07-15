namespace NotchAgent.Windows.Providers.Shared;

/// Streaming line reader for JSONL files. Keeps memory flat regardless of
/// file size and tolerates a truncated final line (common while a CLI is
/// still writing). Ported from the Mac app's JSONLReader.swift.
public static class JsonlReader
{
    /// Calls `body` once per complete non-empty line, starting at `offset`.
    /// Returns the offset just past the last complete line consumed — a
    /// trailing line with no newline yet (still being written) is NOT
    /// consumed, so incremental callers re-read it once it completes.
    public static long ForEachLine(string path, long offset, Action<ReadOnlyMemory<byte>> body)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        if (offset > 0)
        {
            stream.Seek(offset, SeekOrigin.Begin);
        }

        long consumed = offset;
        var buffer = new List<byte>(1 << 16);
        var chunk = new byte[1 << 20];
        int read;
        while ((read = stream.Read(chunk, 0, chunk.Length)) > 0)
        {
            buffer.AddRange(chunk.AsSpan(0, read).ToArray());
            int start = 0;
            int newlineIndex;
            while ((newlineIndex = buffer.IndexOf((byte)'\n', start)) >= 0)
            {
                if (newlineIndex > start)
                {
                    body(buffer.GetRange(start, newlineIndex - start).ToArray());
                }
                consumed += newlineIndex - start + 1;
                start = newlineIndex + 1;
            }
            buffer.RemoveRange(0, start);
        }
        return consumed;
    }

    /// Last `maxBytes` of the file, aligned to the first full line inside the window.
    public static List<byte[]> TailLines(string path, int maxBytes)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        long size = stream.Length;
        long offset = size > maxBytes ? size - maxBytes : 0;

        bool firstLineIsPartial = offset > 0;
        if (offset > 0)
        {
            stream.Seek(offset - 1, SeekOrigin.Begin);
            int b = stream.ReadByte();
            if (b == '\n') firstLineIsPartial = false;
        }
        stream.Seek(offset, SeekOrigin.Begin);

        using var ms = new MemoryStream();
        stream.CopyTo(ms);
        var data = ms.ToArray();
        if (data.Length == 0) return new List<byte[]>();

        var lines = new List<byte[]>();
        int start = 0;
        for (int i = 0; i < data.Length; i++)
        {
            if (data[i] == (byte)'\n')
            {
                if (i > start) lines.Add(data[start..i]);
                start = i + 1;
            }
        }
        if (start < data.Length) lines.Add(data[start..]);

        if (firstLineIsPartial && lines.Count > 0)
        {
            lines.RemoveAt(0);
        }
        return lines;
    }

    private static int IndexOf(this List<byte> list, byte value, int start)
    {
        for (int i = start; i < list.Count; i++)
        {
            if (list[i] == value) return i;
        }
        return -1;
    }
}
