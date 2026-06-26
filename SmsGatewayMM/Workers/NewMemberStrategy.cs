namespace SmsGatewayMM.Workers;

using SmsGatewayMM.Config;

class NewMemberStrategy : ISmsWorkerStrategy
{
    private readonly SmsMmConfig _config;
    public NewMemberStrategy(SmsMmConfig config) => _config = config;

    public string FeedName => "NewMember";
    public string SubsystemName => _config.LogSubsystemNewMember;
    public string CheckProcedure => "SMSGateway.PE_CHECK_NEW_MEMBER_QUEUE_MM";
    public string GetProcedure => "SMSGateway.PE_GET_NEXT_NEW_MEMBER_MM_V2";
    public string ConfirmProcedure => "SMSGateway.PE_CONFIRM_SENT_NEW_MEMBER_MM";
    public string ResetProcedure => "SMSGateway.PE_RESET_FAILED_NEW_MEMBER_MM";
    public string ReaperProcedure => "SMSGateway.PE_REAP_STUCK_NEW_MEMBER_MM";
}
