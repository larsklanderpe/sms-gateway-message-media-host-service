namespace SmsGatewayMM.Workers;

using SmsGatewayMM.Config;

class TierUpgradeStrategy : ISmsWorkerStrategy
{
    private readonly SmsMmConfig _config;
    public TierUpgradeStrategy(SmsMmConfig config) => _config = config;

    public string FeedName => "TierUpgrade";
    public string SubsystemName => _config.LogSubsystemTierUpgrade;
    public string CheckProcedure => "SMSGateway.PE_CHECK_TIER_UPGRADE_QUEUE_MM";
    public string GetProcedure => "SMSGateway.PE_GET_NEXT_TIER_UPGRADE_MM";
}
