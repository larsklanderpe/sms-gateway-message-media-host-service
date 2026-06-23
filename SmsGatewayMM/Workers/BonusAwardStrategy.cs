namespace SmsGatewayMM.Workers;

using SmsGatewayMM.Config;

class BonusAwardStrategy : ISmsWorkerStrategy
{
    private readonly SmsMmConfig _config;
    public BonusAwardStrategy(SmsMmConfig config) => _config = config;

    public string FeedName => "BonusAward";
    public string SubsystemName => _config.LogSubsystemBonusAward;
    public string CheckProcedure => "SMSGateway.PE_CHECK_BONUS_AWARD_QUEUE_MM";
    public string GetProcedure => "SMSGateway.PE_GET_NEXT_BONUS_AWARD_MM";
}
