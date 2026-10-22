// Original local build adapter; not a compiler replacement. See Invoke-Moon016.ps1.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

class MooncPathAdapter {
    static string Quote(string value) {
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value) {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') result.Append('\\', slashes * 2 + 1);
            else result.Append('\\', slashes);
            result.Append(c);
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        return result.Append('"').ToString();
    }

    static int Main(string[] args) {
        bool formatting = Path.GetFileNameWithoutExtension(
            Process.GetCurrentProcess().MainModule.FileName).StartsWith("moonfmt-");
        string variable = formatting ? "MOONGRAPHML_REAL_FORMATTER" : "MOONGRAPHML_REAL_COMPILER";
        string compiler = Environment.GetEnvironmentVariable(variable);
        if (String.IsNullOrEmpty(compiler)) {
            Console.Error.WriteLine(variable + " must name the original tool");
            return 2;
        }
        var command = new StringBuilder();
        foreach (string original in args) {
            string value = original;
            // Normalize only extended drive paths, including .mi:alias arguments.
            // Do not rewrite arbitrary source text, UNC shares, or other arguments.
            if (value.StartsWith(@"\\?\") && value.Length > 6 &&
                Char.IsLetter(value[4]) && value[5] == ':')
                value = value.Substring(4);
            if (command.Length > 0) command.Append(' ');
            command.Append(Quote(value));
        }
        var info = new ProcessStartInfo(compiler, command.ToString());
        info.UseShellExecute = false;
        using (var child = Process.Start(info)) {
            child.WaitForExit();
            return child.ExitCode;
        }
    }
}
