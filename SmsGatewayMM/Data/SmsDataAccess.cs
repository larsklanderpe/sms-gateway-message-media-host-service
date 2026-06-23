namespace SmsGatewayMM.Data;

using Dapper;
using Microsoft.Data.SqlClient;
using SmsGatewayMM.Models;
using SmsGatewayMM.Workers;
using System.Data;

class SmsDataAccess
{
    private readonly string _connectionString;

    public SmsDataAccess(string connectionString) => _connectionString = connectionString;

    public bool HasPending(ISmsWorkerStrategy strategy)
    {
        using var conn = new SqlConnection(_connectionString);
        var result = conn.QueryFirstOrDefault<int>(
            strategy.CheckProcedure,
            commandType: CommandType.StoredProcedure);
        return result > 0;
    }

    public SmsReadyMessage? GetNext(ISmsWorkerStrategy strategy)
    {
        using var conn = new SqlConnection(_connectionString);
        var row = conn.QueryFirstOrDefault<dynamic>(
            strategy.GetProcedure,
            commandType: CommandType.StoredProcedure);

        if (row == null) return null;

        // Column names must match the new per-feed Get SPs exactly.
        // New SPs standardise to: id, venue_id, source_number, dest_number, content
        return new SmsReadyMessage(
            Id: (int)row.id,
            VenueId: (int)row.venue_id,
            SourceNumber: (string)row.source_number,
            DestinationNumber: (string)row.dest_number,
            Content: (string)row.content
        );
    }

    public void ConfirmSent(ISmsWorkerStrategy strategy, int id, int venueId)
    {
        using var conn = new SqlConnection(_connectionString);
        conn.Execute(
            strategy.ConfirmProcedure,
            new { id, venue_id = venueId },
            commandType: CommandType.StoredProcedure);
    }

    public void ResetFailed(ISmsWorkerStrategy strategy, int id, int venueId)
    {
        using var conn = new SqlConnection(_connectionString);
        conn.Execute(
            strategy.ResetProcedure,
            new { id, venue_id = venueId },
            commandType: CommandType.StoredProcedure);
    }

    public void RunReaper(ISmsWorkerStrategy strategy, int cutoffMinutes)
    {
        using var conn = new SqlConnection(_connectionString);
        conn.Execute(
            strategy.ReaperProcedure,
            new { cutoff_minutes = cutoffMinutes },
            commandType: CommandType.StoredProcedure);
    }
}
