namespace SmsGatewayMM.Config;

record SmsMmConfig
{
    public int PollIntervalSeconds { get; init; } = 10;
    public string BarrelConnectionString { get; init; } = "";
    public string MessageMediaApiKey { get; init; } = "";
    public string MessageMediaApiSecret { get; init; } = "";
    public string MessageMediaBaseUrl { get; init; } = "https://api.messagemedia.com";
    public string LogRoot { get; init; } = @"C:\Logs\SMSGMM";
    public string LogSubsystemNewMember { get; init; } = "SMSGMM_NewMember";
    public string LogSubsystemTierUpgrade { get; init; } = "SMSGMM_TierUpgrade";
    public string LogSubsystemBonusAward { get; init; } = "SMSGMM_BonusAward";
}
