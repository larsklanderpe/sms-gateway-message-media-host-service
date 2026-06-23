-- ============================================================
-- SP:      SMSGateway.PE_GET_NEXT_NEW_MEMBER_MM_V2
-- Created: 2026-06-23
-- ============================================================
-- History:
--   2026-06-23 | LMDTS-64 two-phase delivery: claim only (InTransmission=1),
--              | SubmittedToHostSMS=1 deferred to PE_CONFIRM_SENT_NEW_MEMBER_MM.
--              | V1 (PE_GET_NEXT_NEW_MEMBER_MM) retained for rollback compatibility.
-- ============================================================
-- PURPOSE:
--   Claim phase of two-phase delivery. Marks InTransmission=1 and records the
--   claim timestamp, then returns the ready-to-send message. Does NOT set
--   SubmittedToHostSMS=1 -- that is set by PE_CONFIRM_SENT_NEW_MEMBER_MM after
--   HTTP 202 from MessageMedia. On send failure PE_RESET_FAILED_NEW_MEMBER_MM
--   clears InTransmission so the record re-enters the queue.
--
-- OUTPUT COLUMNS (standardised across all three feeds -- identical to V1):
--   id             INT           -- NewMember_HostSMSID
--   venue_id       INT
--   source_number  VARCHAR(11)   -- TextMessageSource (sender ID)
--   dest_number    VARCHAR(25)   -- HostMobile formatted to +61
--   content        VARCHAR(1024) -- TextMessageBody with tokens merged
-- ============================================================

CREATE OR ALTER PROCEDURE [SMSGateway].[PE_GET_NEXT_NEW_MEMBER_MM_V2]
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
            -- LMDTS-64: claim only -- SubmittedToHostSMS=1 set by PE_CONFIRM_SENT_NEW_MEMBER_MM
            UPDATE [SMSGateway].[NewMember_Host_SMS]
            SET InTransmission = 1,
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
