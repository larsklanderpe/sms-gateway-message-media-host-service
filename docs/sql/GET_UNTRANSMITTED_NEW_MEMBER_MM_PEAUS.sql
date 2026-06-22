-- ============================================================
-- SP:      SMSGateway.GET_UNTRANSMITTED_NEW_MEMBER_MM
-- Source:  PE_Barrel_Cloud_Master (PEAUS)
-- Captured: 2026-06-22
-- ============================================================
-- History:
--   2026-06-22 | Captured from PENEXUS for analysis / rewrite reference
-- ============================================================
-- OUTPUT COLUMNS (final SELECT):
--   playeroffers_smsid   int     (alias for NewMember_HostSMSID)
--   VenueID              varchar(4)
--   source_number        varchar(11)
--   destination_number   varchar(25)
--   content              varchar(1024)
--
-- NOTE: @venueid declared as varchar(4) -- used in string concat for @userID
-- NOTE: PEAUS and PENEXUS are IDENTICAL for this SP
-- ============================================================

CREATE procedure [SMSGateway].[GET_UNTRANSMITTED_NEW_MEMBER_MM]
WITH RECOMPILE
as
BEGIN
    declare @NewMember_HostSMSID int
    declare @venueid varchar(4)

    select  @venueID = hs.VenueID, @NewMember_HostSMSID = hs.[NewMember_HostSMSID]
    from    [SMSGateway].[NewMember_Host_SMS] hs inner join (select top 1  VenueID, [NewMember_HostSMSID]
    from    [SMSGateway].[NewMember_Host_SMS]
    where   iseligibleforsms = 1 and
            submittedtoHostSMS = 0 and
            IsNull(InTransmission, 0) = 0
            order by venueid, NewMember_HostSMSID) nmhs on hs.venueid = nmhs.venueid and hs.NewMember_HostSMSID = nmhs.NewMember_HostSMSID

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

    if exists (select * FROM [SMSGateway].[NewMember_Host_SMS] pos
        inner join [SMSGateway].[Message_Body_Model] mbm on pos.[PlayerCommMessageID] = mbm.thirdpartypromotionid
        inner join [SMSGateway].[ThirdPartySMSIDS] tps on pos.ThirdPartyHostID = tps.HostThirdPartyID
        WHERE   [NewMember_HostSMSID] = @NewMember_HostSMSID
        and HostSMSActiveForNewMember = 1
        and pos.PlayerCommMessageType = 1
        and pos.VenueID = @VenueID)
    BEGIN
        SELECT @cmsplayerid = 'xxxx' + right(CMSPlayerID,3),
               @shortName = FirstName + ' ' + Left(LastName, 1) + '.',
               @FirstName = Firstname,
               @userID = @venueid + cmsplayerid + playeraccountnum,
               @destinationNumber = HostMobile,
               @consumerMobile = PlayerMobile,
               @timeAwarded = ImportTimestamp,
               @hostID = tps.HostThirdPartyID,
               @ReferenceDescription = 'NEW MEMBER',
               @messageModel = TextMessageBody,
               @messageHeader = TextMessageSource
        FROM [SMSGateway].[NewMember_Host_SMS] pos
            inner join [SMSGateway].[Message_Body_Model] mbm on pos.[PlayerCommMessageID] = mbm.thirdpartypromotionid
            inner join [SMSGateway].[ThirdPartySMSIDS] tps on pos.ThirdPartyHostID = tps.HostThirdPartyID
        WHERE   [NewMember_HostSMSID] = @NewMember_HostSMSID
        and HostSMSActiveForNewMember = 1
        and pos.PlayerCommMessageType = 1
        and pos.VenueID = @VenueID

        -- Token substitution (subset only -- no surname/PlayerLevelDescription/offerdescription for NewMember)
        select @messageModel = replace(@messageModel, '#shortname#', @shortName)
        select @messageModel = replace(@messageModel, '#firstname#', @firstName)
        select @messageModel = replace(@messageModel, '#cmsplayerid#', @cmsplayerid)
        select @messageModel = replace(@messageModel, '#timeawarded#', IsNull(@timeawarded,getdate()))

        if Isnull(@consumerMobile, '00') = '00' or len(@consumermobile) < 9
        BEGIN
            select @messageModel = '\nPLEASE NOTE:MEMBER HAS NO VALID MOBILE\n' + @messageModel
        END

        if left(@destinationNumber,2) = '04'
        BEGIN
            select @destinationNumber = '+61' + right(@destinationNumber, len(@destinationNumber)-1)
        end

        if Isnull(@NewMember_HostSMSID,0) > 0
        BEGIN
            -- NOTE: UPDATE does not filter by VenueID (PK is unique so safe, but inconsistent with TierUpgrade)
            update [SMSGateway].[NewMember_Host_SMS]
            set intransmission = 1,
                SubmittedToHostSMS = 1,
                SubmittedToHostSMSDateTime = getdate()
            where [NewMember_HostSMSID] = @NewMember_HostSMSID

            if len(IsNull(@destinationNumber, '+614')) > 4
            BEGIN
                INSERT INTO [SMSGateway].[Message_Body_Audit_Log]
                       (VenueID, [ReferenceDescription], [TextMessageSource], [UserID], [HostID],
                        [TextMessageMergedContent], [DestinationNumber], [TransmissionTime], [Message_ID], [SubSystemSource])
                select @VenueID, @ReferenceDescription, @messageHeader, @userID, @hostID,
                       @messageModel, @destinationNumber, getdate(), null, 'NEWMEMBER'

                select  @NewMember_HostSMSID as playeroffers_smsid,
                        @VenueID as VenueID,
                        @messageHeader as source_number,
                        @destinationNumber as destination_number,
                        @messageModel as content
            end
        end
    end
    else
    BEGIN
        update [SMSGateway].[NewMember_Host_SMS]
        set IsEligibleForSMS = 0
        where VenueID = @VenueID and NewMember_HostSMSID = @NewMember_HostSMSID
    end
end
