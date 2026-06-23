-- ============================================================
-- SP:      SMSGateway.PE_GET_NEXT_TIER_UPGRADE_MM
-- Created: 2026-06-22
-- ============================================================
-- History:
--   2026-06-22 | Written for sms-gateway-message-media-host-service build 1.0.x.x
-- ============================================================
-- PURPOSE:
--   Gets the next pending TierUpgrade record, marks it InTransmission, writes
--   the audit log entry, and returns the ready-to-send message.
--   Called by the TierUpgrade SmsWorker immediately after
--   PE_CHECK_TIER_UPGRADE_QUEUE_MM returns a row.
--
-- OUTPUT COLUMNS (standardised across all three feeds):
--   id             INT           -- TierUpgrades_HostSMSID
--   venue_id       INT
--   source_number  VARCHAR(11)   -- TextMessageSource (sender ID)
--   dest_number    VARCHAR(25)   -- HostMobile formatted to +61
--   content        VARCHAR(1024) -- TextMessageBody with tokens merged
--
-- TOKENS SUBSTITUTED: #shortname# #firstname# #cmsplayerid#
--                     #PlayerLevelDescription# #timeawarded#
--
-- DESIGN NOTES:
--   - Added IF EXISTS guard for HostSMSActiveForTiering before data SELECT.
--     Old GET_UNTRANSMITTED_TIER_UPGRADE_MM had no guard -- if the host was
--     inactive the UPDATE still ran, leaving records stuck as InTransmission
--     with no message sent. With independent workers this is no longer
--     acceptable (it blocks the entire TierUpgrade feed). Inactive records
--     now get IsEligibleForSMS = 0 cleanly.
--   - Added VenueID to output SELECT (was missing from both clouds in the
--     old sub-SP).
--   - @venueid as INT to match the original SP; @userID concat uses CAST.
-- ============================================================

CREATE OR ALTER PROCEDURE [SMSGateway].[PE_GET_NEXT_TIER_UPGRADE_MM]
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @TierUpgrades_HostSMSID INT
    DECLARE @venueid INT

    SELECT TOP 1 @TierUpgrades_HostSMSID = [TierUpgrades_HostSMSID],
                 @VenueID = VenueID
    FROM [SMSGateway].[TierUpgrades_Host_SMS]
    WHERE IsEligibleForSMS = 1
      AND SubmittedToHostSMS = 0
      AND ISNULL(InTransmission, 0) = 0
      AND ISNULL(SuppressedFromTransmission, 0) = 0
    ORDER BY UpgradeAwardedDateTime, VenueID

    DECLARE @shortname VARCHAR(255)
    DECLARE @firstname VARCHAR(255)
    DECLARE @cmsplayerid VARCHAR(8)
    DECLARE @ReferenceDescription VARCHAR(255)
    DECLARE @userID VARCHAR(20)
    DECLARE @hostID VARCHAR(10)
    DECLARE @PlayerLevelDescription VARCHAR(255)
    DECLARE @timeAwarded VARCHAR(255)
    DECLARE @destinationNumber VARCHAR(25)
    DECLARE @consumerMobile VARCHAR(25)
    DECLARE @messageModel VARCHAR(1024)
    DECLARE @messageHeader VARCHAR(11)

    IF EXISTS (
        SELECT 1 FROM [SMSGateway].[TierUpgrades_Host_SMS] pos
        INNER JOIN [SMSGateway].[Message_Body_Model] mbm
            ON pos.[PlayerCommMessageID] = mbm.thirdpartypromotionid AND pos.VenueID = mbm.VenueID
        INNER JOIN [SMSGateway].[ThirdPartySMSIDS] tps
            ON pos.ThirdPartyHostID = tps.HostThirdPartyID
        WHERE [TierUpgrades_HostSMSID] = @TierUpgrades_HostSMSID
          AND HostSMSActiveForTiering = 1
          AND pos.PlayerCommMessageType = 1
          AND pos.VenueID = @VenueID
    )
    BEGIN
        SELECT @cmsplayerid = 'xxxx' + RIGHT(CMSPlayerID, 3),
               @shortName = FirstName + ' ' + LEFT(LastName, 1) + '.',
               @FirstName = FirstName,
               @userID = CAST(@venueid AS VARCHAR(10)) + CMSPlayerID + PlayerAccountNum,
               @destinationNumber = HostMobile,
               @consumerMobile = PlayerMobile,
               @PlayerLevelDescription = NewTierName,
               @timeAwarded = UpgradeAwardedDateTime,
               @hostID = tps.HostThirdPartyID,
               @ReferenceDescription = 'TIER UPGRADES',
               @messageModel = TextMessageBody,
               @messageHeader = TextMessageSource
        FROM [SMSGateway].[TierUpgrades_Host_SMS] pos
        INNER JOIN [SMSGateway].[Message_Body_Model] mbm
            ON pos.[PlayerCommMessageID] = mbm.thirdpartypromotionid AND pos.VenueID = mbm.VenueID
        INNER JOIN [SMSGateway].[ThirdPartySMSIDS] tps
            ON pos.ThirdPartyHostID = tps.HostThirdPartyID
        WHERE [TierUpgrades_HostSMSID] = @TierUpgrades_HostSMSID
          AND HostSMSActiveForTiering = 1
          AND pos.PlayerCommMessageType = 1
          AND pos.VenueID = @VenueID

        SELECT @messageModel = REPLACE(@messageModel, '#shortname#', @shortName)
        SELECT @messageModel = REPLACE(@messageModel, '#firstname#', @firstName)
        SELECT @messageModel = REPLACE(@messageModel, '#cmsplayerid#', @cmsplayerid)
        SELECT @messageModel = REPLACE(@messageModel, '#PlayerLevelDescription#', @PlayerLevelDescription)
        SELECT @messageModel = REPLACE(@messageModel, '#timeawarded#', ISNULL(@timeAwarded, GETDATE()))

        IF ISNULL(@consumerMobile, '00') = '00' OR LEN(@consumerMobile) < 9
            SELECT @messageModel = '\nPLEASE NOTE:MEMBER HAS NO VALID MOBILE\n' + @messageModel

        IF LEFT(@destinationNumber, 2) = '04'
            SELECT @destinationNumber = '+61' + RIGHT(@destinationNumber, LEN(@destinationNumber) - 1)

        IF ISNULL(@TierUpgrades_HostSMSID, 0) > 0
        BEGIN
            UPDATE [SMSGateway].[TierUpgrades_Host_SMS]
            SET InTransmission = 1,
                SubmittedToHostSMS = 1,
                SubmittedToHostSMSDateTime = GETDATE()
            WHERE [TierUpgrades_HostSMSID] = @TierUpgrades_HostSMSID
              AND VenueID = @VenueID

            IF LEN(ISNULL(@destinationNumber, '+614')) > 4
            BEGIN
                INSERT INTO [SMSGateway].[Message_Body_Audit_Log]
                       ([VenueID], [ReferenceDescription], [TextMessageSource], [UserID], [HostID],
                        [TextMessageMergedContent], [DestinationNumber], [TransmissionTime], [Message_ID], [SubSystemSource])
                SELECT @VenueID, @ReferenceDescription, @messageHeader, @userID, @hostID,
                       @messageModel, @destinationNumber, GETDATE(), NULL, 'TIERUPGRADES'

                SELECT @TierUpgrades_HostSMSID AS id,
                       @VenueID               AS venue_id,
                       @messageHeader         AS source_number,
                       @destinationNumber     AS dest_number,
                       @messageModel          AS content
            END
        END
    END
    ELSE
    BEGIN
        UPDATE [SMSGateway].[TierUpgrades_Host_SMS]
        SET IsEligibleForSMS = 0
        WHERE VenueID = @VenueID AND TierUpgrades_HostSMSID = @TierUpgrades_HostSMSID
    END
END
