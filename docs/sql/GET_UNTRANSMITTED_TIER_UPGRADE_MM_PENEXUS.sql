-- ============================================================
-- SP:      SMSGateway.GET_UNTRANSMITTED_TIER_UPGRADE_MM
-- Source:  PE_Barrel_Cloud_Master (PENEXUS)
-- Captured: 2026-06-22
-- ============================================================
-- History:
--   2026-06-22 | Captured from PENEXUS for analysis / rewrite reference
-- ============================================================
-- OUTPUT COLUMNS (final SELECT):
--   playeroffers_smsid   int     (alias for TierUpgrades_HostSMSID)
--   source_number        varchar(11)
--   destination_number   varchar(25)
--   content              varchar(1024)
--
-- BUG: VenueID is NOT in the output SELECT even though @VenueID is populated.
--      NewMember and BonusAward both return VenueID -- this is an inconsistency.
--      The new per-feed SP (PE_GET_NEXT_TIER_UPGRADE_MM) will fix this.
--
-- NOTE: @venueid declared as int (vs varchar(4) in NewMember)
-- NOTE: No IF EXISTS host-active check before the SELECT -- if HostSMSActiveForTiering = 0,
--       the data SELECT returns nothing, @messageModel is NULL, audit log is skipped,
--       but the UPDATE (intransmission=1, SubmittedToHostSMS=1) still runs if
--       @TierUpgrades_HostSMSID is non-null. Records could get stuck.
--       New SP will add explicit host-active guard.
-- NOTE: PEAUS and PENEXUS are IDENTICAL for this SP
-- ============================================================

CREATE procedure [SMSGateway].[GET_UNTRANSMITTED_TIER_UPGRADE_MM]
WITH RECOMPILE
as
    declare @TierUpgrades_HostSMSID int
    declare @venueidstring varchar(4)
    declare @venueid int

    select  @TierUpgrades_HostSMSID = [TierUpgrades_HostSMSID],
            @VenueID = VenueID
    from    [SMSGateway].[TierUpgrades_Host_SMS] hs
    where   [TierUpgrades_HostSMSID] in (select top 1  [TierUpgrades_HostSMSID]
    from    [SMSGateway].[TierUpgrades_Host_SMS]
    where   iseligibleforsms = 1 and
            submittedtoHostSMS = 0 and
            IsNull(InTransmission, 0) = 0
    order by UpgradeAwardedDateTime, VenueID
    ) and iseligibleforsms = 1 and
            submittedtoHostSMS = 0 and
            IsNull(InTransmission, 0) = 0

    declare @shortname varchar(255)
    declare @firstname varchar(255)
    declare @cmsplayerid varchar(8)
    declare @ReferenceDescription varchar(255)
    declare @userID varchar(20)
    declare @hostID varchar(10)
    declare @PlayerLevelDescription varchar(255)
    declare @OfferDescription varchar(255)
    declare @timeAwarded varchar(255)
    declare @destinationNumber varchar(25)
    declare @consumerMobile varchar(25)
    declare @messageModel varchar(1024)
    declare @messageHeader varchar(11)

    -- NOTE: No IF EXISTS guard here -- host-inactive records will still get marked InTransmission
    SELECT @cmsplayerid = 'xxxx' + right(CMSPlayerID,3),
           @shortName = FirstName + ' ' + Left(LastName, 1) + '.',
           @FirstName = Firstname,
           @userID = @venueid + cmsplayerid + playeraccountnum,
           @destinationNumber = HostMobile,
           @consumerMobile = PlayerMobile,
           @PlayerLevelDescription = NewTierName,
           @timeAwarded = UpgradeAwardedDateTime,
           @hostID = tps.HostThirdPartyID,
           @ReferenceDescription = 'TIER UPGRADES',
           @messageModel = TextMessageBody,
           @messageHeader = TextMessageSource
    FROM [SMSGateway].[TierUpgrades_Host_SMS] pos
        inner join [SMSGateway].[Message_Body_Model] mbm on pos.[PlayerCommMessageID] = mbm.thirdpartypromotionid and pos.venueid = mbm.venueid
        inner join [SMSGateway].[ThirdPartySMSIDS] tps on pos.ThirdPartyHostID = tps.HostThirdPartyID
    WHERE   [TierUpgrades_HostSMSID] = @TierUpgrades_HostSMSID
    and HostSMSActiveForTiering = 1
    and pos.PlayerCommMessageType = 1
    and pos.VenueID = @VenueID

    -- Token substitution (includes #PlayerLevelDescription# unlike NewMember)
    select @messageModel = replace(@messageModel, '#shortname#', @shortName)
    select @messageModel = replace(@messageModel, '#firstname#', @firstName)
    select @messageModel = replace(@messageModel, '#cmsplayerid#', @cmsplayerid)
    select @messageModel = replace(@messageModel, '#PlayerLevelDescription#', @PlayerLevelDescription)
    select @messageModel = replace(@messageModel, '#timeawarded#', IsNull(@timeawarded,getdate()))

    if Isnull(@consumerMobile, '00') = '00' or len(@consumermobile) < 9
    BEGIN
        select @messageModel = '\nPLEASE NOTE:MEMBER HAS NO VALID MOBILE\n' + @messageModel
    END

    if left(@destinationNumber,2) = '04'
    BEGIN
        select @destinationNumber = '+61' + right(@destinationNumber, len(@destinationNumber)-1)
    end

    if Isnull(@TierUpgrades_HostSMSID,0) > 0
    BEGIN
        update [SMSGateway].[TierUpgrades_Host_SMS]
        set intransmission = 1,
            SubmittedToHostSMS = 1,
            SubmittedToHostSMSDateTime = getdate()
        where [TierUpgrades_HostSMSID] = @TierUpgrades_HostSMSID and VenueID = @VenueID

        if len(IsNull(@destinationNumber, '+614')) > 4
        BEGIN
            INSERT INTO [SMSGateway].[Message_Body_Audit_Log]
                   ([VenueID], [ReferenceDescription], [TextMessageSource], [UserID], [HostID],
                    [TextMessageMergedContent], [DestinationNumber], [TransmissionTime], [Message_ID], [SubSystemSource])
            select @VenueID, @ReferenceDescription, @messageHeader, @userID, @hostID,
                   @messageModel, @destinationNumber, getdate(), null, 'TIERUPGRADES'

            -- BUG: VenueID missing from output SELECT
            select  @TierUpgrades_HostSMSID as playeroffers_smsid,
                    @messageHeader as source_number,
                    @destinationNumber as destination_number,
                    @messageModel as content
        end
    end
