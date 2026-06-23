-- ============================================================
-- SP:      SMSGateway.PE_GET_NEXT_NEW_MEMBER_MM
-- Created: 2026-06-22
-- ============================================================
-- History:
--   2026-06-22 | Written for sms-gateway-message-media-host-service build 6.6.x.x
-- ============================================================
-- PURPOSE:
--   Gets the next pending NewMember record, marks it InTransmission, writes
--   the audit log entry, and returns the ready-to-send message.
--   Called by the NewMember SmsWorker immediately after PE_CHECK_NEW_MEMBER_QUEUE_MM
--   returns a row.
--
-- OUTPUT COLUMNS (standardised across all three feeds):
--   id             INT           -- NewMember_HostSMSID
--   venue_id       INT
--   source_number  VARCHAR(11)   -- TextMessageSource (sender ID)
--   dest_number    VARCHAR(25)   -- HostMobile formatted to +61
--   content        VARCHAR(1024) -- TextMessageBody with tokens merged
--
-- TOKENS SUBSTITUTED: #shortname# #firstname# #cmsplayerid# #timeawarded#
-- (No #surname# #lastname# #PlayerLevelDescription# #offerdescription# for NewMember)
--
-- DESIGN NOTES:
--   - IF EXISTS guard before data SELECT ensures inactive-host records are
--     suppressed cleanly rather than being marked InTransmission with no send.
--     This corrects a known issue in the old GET_UNTRANSMITTED_NEW_MEMBER_MM.
--   - @venueid kept as VARCHAR(4) to match string concat for @userID, same
--     as the original SP.
-- ============================================================

-- ============================================================
-- RENAME GATE
-- ============================================================
IF OBJECT_ID('[SMSGateway].[PE_GET_NEXT_NEW_MEMBER_MM]') IS NOT NULL
BEGIN
    IF OBJECT_ID('[SMSGateway].[PE_GET_NEXT_NEW_MEMBER_MM_BAK]') IS NOT NULL
        DROP PROCEDURE [SMSGateway].[PE_GET_NEXT_NEW_MEMBER_MM_BAK]
    EXEC sp_rename '[SMSGateway].[PE_GET_NEXT_NEW_MEMBER_MM]', 'PE_GET_NEXT_NEW_MEMBER_MM_BAK', 'OBJECT'
END
GO

CREATE OR ALTER PROCEDURE [SMSGateway].[PE_GET_NEXT_NEW_MEMBER_MM]
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @NewMember_HostSMSID INT
    DECLARE @venueid VARCHAR(4)

    SELECT TOP 1 @venueID = hs.VenueID, @NewMember_HostSMSID = hs.[NewMember_HostSMSID]
    FROM [SMSGateway].[NewMember_Host_SMS] hs
    INNER JOIN (
        SELECT TOP 1 VenueID, [NewMember_HostSMSID]
        FROM [SMSGateway].[NewMember_Host_SMS]
        WHERE IsEligibleForSMS = 1
          AND SubmittedToHostSMS = 0
          AND ISNULL(InTransmission, 0) = 0
          AND ISNULL(SuppressedFromTransmission, 0) = 0
        ORDER BY VenueID, NewMember_HostSMSID
    ) nmhs ON hs.VenueID = nmhs.VenueID AND hs.NewMember_HostSMSID = nmhs.NewMember_HostSMSID

    DECLARE @shortname VARCHAR(255)
    DECLARE @firstname VARCHAR(255)
    DECLARE @cmsplayerid VARCHAR(8)
    DECLARE @ReferenceDescription VARCHAR(255)
    DECLARE @userID VARCHAR(20)
    DECLARE @hostID VARCHAR(10)
    DECLARE @timeAwarded VARCHAR(255)
    DECLARE @destinationNumber VARCHAR(25)
    DECLARE @consumerMobile VARCHAR(25)
    DECLARE @messageModel VARCHAR(1024)
    DECLARE @messageHeader VARCHAR(11)

    IF EXISTS (
        SELECT 1 FROM [SMSGateway].[NewMember_Host_SMS] pos
        INNER JOIN [SMSGateway].[Message_Body_Model] mbm
            ON pos.[PlayerCommMessageID] = mbm.thirdpartypromotionid
        INNER JOIN [SMSGateway].[ThirdPartySMSIDS] tps
            ON pos.ThirdPartyHostID = tps.HostThirdPartyID
        WHERE [NewMember_HostSMSID] = @NewMember_HostSMSID
          AND HostSMSActiveForNewMember = 1
          AND pos.PlayerCommMessageType = 1
          AND pos.VenueID = @VenueID
    )
    BEGIN
        SELECT @cmsplayerid = 'xxxx' + RIGHT(CMSPlayerID, 3),
               @shortName = FirstName + ' ' + LEFT(LastName, 1) + '.',
               @FirstName = FirstName,
               @userID = @venueid + CMSPlayerID + PlayerAccountNum,
               @destinationNumber = HostMobile,
               @consumerMobile = PlayerMobile,
               @timeAwarded = ImportTimestamp,
               @hostID = tps.HostThirdPartyID,
               @ReferenceDescription = 'NEW MEMBER',
               @messageModel = TextMessageBody,
               @messageHeader = TextMessageSource
        FROM [SMSGateway].[NewMember_Host_SMS] pos
        INNER JOIN [SMSGateway].[Message_Body_Model] mbm
            ON pos.[PlayerCommMessageID] = mbm.thirdpartypromotionid
        INNER JOIN [SMSGateway].[ThirdPartySMSIDS] tps
            ON pos.ThirdPartyHostID = tps.HostThirdPartyID
        WHERE [NewMember_HostSMSID] = @NewMember_HostSMSID
          AND HostSMSActiveForNewMember = 1
          AND pos.PlayerCommMessageType = 1
          AND pos.VenueID = @VenueID

        SELECT @messageModel = REPLACE(@messageModel, '#shortname#', @shortName)
        SELECT @messageModel = REPLACE(@messageModel, '#firstname#', @firstName)
        SELECT @messageModel = REPLACE(@messageModel, '#cmsplayerid#', @cmsplayerid)
        SELECT @messageModel = REPLACE(@messageModel, '#timeawarded#', ISNULL(@timeAwarded, GETDATE()))

        IF ISNULL(@consumerMobile, '00') = '00' OR LEN(@consumerMobile) < 9
            SELECT @messageModel = '\nPLEASE NOTE:MEMBER HAS NO VALID MOBILE\n' + @messageModel

        IF LEFT(@destinationNumber, 2) = '04'
            SELECT @destinationNumber = '+61' + RIGHT(@destinationNumber, LEN(@destinationNumber) - 1)

        IF ISNULL(@NewMember_HostSMSID, 0) > 0
        BEGIN
            UPDATE [SMSGateway].[NewMember_Host_SMS]
            SET InTransmission = 1,
                SubmittedToHostSMS = 1,
                SubmittedToHostSMSDateTime = GETDATE()
            WHERE [NewMember_HostSMSID] = @NewMember_HostSMSID
              AND VenueID = @VenueID

            IF LEN(ISNULL(@destinationNumber, '+614')) > 4
            BEGIN
                INSERT INTO [SMSGateway].[Message_Body_Audit_Log]
                       (VenueID, [ReferenceDescription], [TextMessageSource], [UserID], [HostID],
                        [TextMessageMergedContent], [DestinationNumber], [TransmissionTime], [Message_ID], [SubSystemSource])
                SELECT @VenueID, @ReferenceDescription, @messageHeader, @userID, @hostID,
                       @messageModel, @destinationNumber, GETDATE(), NULL, 'NEWMEMBER'

                SELECT @NewMember_HostSMSID AS id,
                       CAST(@VenueID AS INT)  AS venue_id,
                       @messageHeader         AS source_number,
                       @destinationNumber     AS dest_number,
                       @messageModel          AS content
            END
        END
    END
    ELSE
    BEGIN
        UPDATE [SMSGateway].[NewMember_Host_SMS]
        SET IsEligibleForSMS = 0
        WHERE VenueID = @VenueID AND NewMember_HostSMSID = @NewMember_HostSMSID
    END
END
