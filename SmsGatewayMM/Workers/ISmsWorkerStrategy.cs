namespace SmsGatewayMM.Workers;

interface ISmsWorkerStrategy
{
    string FeedName { get; }
    string SubsystemName { get; }
    string CheckProcedure { get; }
    string GetProcedure { get; }
    string ConfirmProcedure { get; }
    string ResetProcedure { get; }
    string ReaperProcedure { get; }
}
