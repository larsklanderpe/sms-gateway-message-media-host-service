namespace SmsGatewayMM.Logging;

using Dapper;
using Microsoft.Data.SqlClient;

class FileLogger
{
    private readonly string _connectionString;
    private readonly string _logRoot;
    private readonly string _serviceName;

    public FileLogger(string connectionString, string logRoot, string serviceName)
    {
        _connectionString = connectionString;
        _logRoot = logRoot;
        _serviceName = serviceName;
        Directory.CreateDirectory(logRoot);
    }

    public void LogStartup(string message) => Write("STARTUP", message, null);
    public void LogError(string subsystem, string message) => Write("ERROR", message, subsystem);

    public void LogNormal(string subsystem, string message)
    {
        if (GetSubsystemLogLevel(subsystem) >= 0) Write("INFO", message, subsystem);
    }

    public void LogDebug(string subsystem, string message)
    {
        if (GetSubsystemLogLevel(subsystem) >= 1) Write("DEBUG", message, subsystem);
    }

    public void LogVerbose(string subsystem, string message)
    {
        if (GetSubsystemLogLevel(subsystem) >= 2) Write("VERBOSE", message, subsystem);
    }

    private int GetSubsystemLogLevel(string subsystemName)
    {
        try
        {
            using var conn = new SqlConnection(_connectionString);
            return conn.QueryFirstOrDefault<int?>(
                "SELECT LogLevel FROM Configuration.Services_Logging " +
                "WHERE ServiceName = @SN AND SubsystemName = @Sub AND LogEnabled = 1",
                new { SN = _serviceName, Sub = subsystemName }) ?? 0;
        }
        catch { return 0; }
    }

    private void Write(string level, string message, string? subsystem)
    {
        var ts = DateTime.Now;
        var line = $"{ts:yyyy-MM-dd HH:mm:ss.fff} [{level}]" +
                   (subsystem != null ? $" [{subsystem}]" : "") +
                   $" {message}";
        var path = Path.Combine(_logRoot, $"SMSGMM_Log_{ts:MM-dd-yyyy}.txt");
        try { File.AppendAllText(path, line + Environment.NewLine); } catch { }
        Console.WriteLine(line);
    }
}
