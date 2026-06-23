-- ============================================================
-- SP:      SMSGateway.PE_GET_NEXT_BONUS_AWARD_MM
-- Created: 2026-06-22
-- ============================================================
-- History:
--   2026-06-22 | Written for sms-gateway-message-media-host-service build 1.0.x.x
-- ============================================================
-- PURPOSE:
--   Gets the next pending BonusAward (PlayerOffers) record, marks it
--   InTransmission, writes the audit log entry, and returns the ready-to-send
--   message. Called by the BonusAward SmsWorker immediately after
--   PE_CHECK_BONUS_AWARD_QUEUE_MM returns a row.
--
-- OUTPUT COLUMNS (standardised across all three feeds):
--   id             INT           -- PlayerOffers_SMSID
--   venue_id       INT
--   source_number  VARCHAR(11)   -- TextMessageSource (sender ID)
--   dest_number    VARCHAR(25)   -- HostMobile formatted to +61
--   content        VARCHAR(1024) -- TextMessageBody with tokens merged
--
-- TOKENS SUBSTITUTED: #firstname# #surname# #lastname# #shortname#
--                     #cmsplayerid# #memberbadge# #cmsplayeridunmasked#
--                     #PlayerLevelDescription# #offerdescription# #timeawarded#
--
-- SAFEGUARDS (PEAUS set):
--   - Orphaned record suppression (host or promo ref missing)
--   - PE Host Guard: suppress if this PE host already transmitted today
-- ============================================================

CREATE OR ALTER PROCEDURE [SMSGateway].[PE_GET_NEXT_BONUS_AWARD_MM]
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @playeroffers_smsid INT
    DECLARE @venueid INT

    SELECT TOP 1 @playeroffers_smsid = PlayerOffers_SMSID,
                 @VenueID = VenueID
    FROM [SMSGateway].[PlayerOffers_SMS]
    WHERE SubmittedToHostSMS = 0
      AND SubmittedToHostSMSDateTime IS NULL
      AND ISNULL(InTransmission, 0) = 0
      AND ISNULL(SuppressedFromTransmission, 0) = 0
    ORDER BY OfferAwardedDateTime

    DECLARE @shortname VARCHAR(255)
    DECLARE @cmsplayerid VARCHAR(10)
    DECLARE @cmsplayeridunmasked VARCHAR(10)
    DECLARE @ReferenceDescription VARCHAR(255)
    DECLARE @userID VARCHAR(25)
    DECLARE @hostID VARCHAR(10)
    DECLARE @firstname VARCHAR(255)
    DECLARE @Surname VARCHAR(255)
    DECLARE @lastname VARCHAR(255)
    DECLARE @memberbadge BIGINT
    DECLARE @PlayerLevelDescription VARCHAR(255)
    DECLARE @OfferDescription VARCHAR(255)
    DECLARE @timeAwarded VARCHAR(255)
    DECLARE @destinationNumber VARCHAR(25)
    DECLARE @consumerMobile VARCHAR(25)
    DECLARE @messageModel VARCHAR(1024)
    DECLARE @messageHeader VARCHAR(11)

    -- Suppress if orphaned (host or promo ref missing)
    IF NOT EXISTS (
        SELECT 1 FROM [SMSGateway].[PlayerOffers_SMS] pos
        INNER JOIN [SMSGateway].[Message_Body_Model] mbm
            ON pos.ThirdPartyHostPromotionID = mbm.thirdpartypromotionid AND pos.VenueID = mbm.VenueID
        INNER JOIN [SMSGateway].[ThirdPartySMSIDS] tps
            ON pos.ThirdPartyHostID = tps.HostThirdPartyID AND pos.VenueID = tps.VenueID
        WHERE PlayerOffers_SMSID = @playeroffers_smsid
          AND pos.VenueID = @VenueID
          AND HostSMSActive = 1
          AND ISNULL(SuppressedFromTransmission, 0) = 0
    )
    BEGIN
        UPDATE [SMSGateway].[PlayerOffers_SMS]
        SET IsEligibleForSMS = 0,
            SubmittedToHostSMS = 0,
            SubmittedToHostSMSDateTime = GETDATE(),
            SuppressedFromTransmission = 1
        WHERE PlayerOffers_SMSID = @playeroffers_smsid AND VenueID = @VenueID
        RETURN
    END

    SELECT @cmsplayerid = 'xxxx' + RIGHT(CMSPlayerID, 3),
           @memberbadge = CONVERT(BIGINT, CMSPlayerID),
           @cmsplayeridunmasked = CONVERT(VARCHAR(8), CONVERT(BIGINT, CMSPlayerID)),
           @shortName = FirstName + ' ' + LEFT(LastName, 1) + '.',
           @FirstName = FirstName,
           @surname = LastName,
           @LastName = LastName,
           @userID = CAST(@venueid AS VARCHAR(10)) + CMSPlayerID + PlayerAccountNum,
           @destinationNumber = HostMobile,
           @consumerMobile = PlayerMobile,
           @PlayerLevelDescription = PlayerLevelDescription,
           @OfferDescription = OfferDescription,
           @timeAwarded = OfferAwardedDateTime,
           @hostID = tps.HostThirdPartyID,
           @ReferenceDescription = PromotionReference,
           @messageModel = TextMessageBody,
           @messageHeader = TextMessageSource
    FROM [SMSGateway].[PlayerOffers_SMS] pos
    INNER JOIN [SMSGateway].[Message_Body_Model] mbm
        ON pos.ThirdPartyHostPromotionID = mbm.thirdpartypromotionid AND pos.VenueID = mbm.VenueID
    INNER JOIN [SMSGateway].[ThirdPartySMSIDS] tps
        ON pos.ThirdPartyHostID = tps.HostThirdPartyID AND pos.VenueID = tps.VenueID
    WHERE PlayerOffers_SMSID = @playeroffers_smsid
      AND pos.VenueID = @VenueID
      AND HostSMSActive = 1
      AND ISNULL(SuppressedFromTransmission, 0) = 0

    -- PE Host Guard: one bonus SMS per PE host per day
    IF EXISTS (
        SELECT 1 FROM [SMSGateway].[ThirdPartySMSIDS]
        WHERE HostThirdPartyID = @hostID
          AND ISNULL(ispehost, 0) = 1
          AND VenueID = @VenueID
    )
    BEGIN
        IF EXISTS (
            SELECT 1 FROM [SMSGateway].[PlayerOffers_SMS]
            WHERE VenueID = @VenueID
              AND ThirdPartyHostID = @hostID
              AND InTransmission = 1
              AND SubmittedToHostSMSDateTime > dbo.current_day_start(GETDATE())
              AND ISNULL(SuppressedFromTransmission, 0) = 0
        )
        BEGIN
            UPDATE [SMSGateway].[PlayerOffers_SMS]
            SET IsEligibleForSMS = 0,
                SubmittedToHostSMS = 0,
                SubmittedToHostSMSDateTime = GETDATE(),
                SuppressedFromTransmission = 1,
                SuppressedFromTransmissionDateTime = GETDATE()
            WHERE PlayerOffers_SMSID = @playeroffers_smsid AND VenueID = @VenueID
            RETURN
        END
    END

    SELECT @messageModel = REPLACE(@messageModel, '#firstname#', @firstName)
    SELECT @messageModel = REPLACE(@messageModel, '#surname#', @surName)
    SELECT @messageModel = REPLACE(@messageModel, '#lastname#', @lastName)
    SELECT @messageModel = REPLACE(@messageModel, '#shortname#', @shortName)
    SELECT @messageModel = REPLACE(@messageModel, '#cmsplayerid#', @cmsplayerid)
    SELECT @messageModel = REPLACE(@messageModel, '#memberbadge#', CONVERT(VARCHAR(10), @memberbadge))
    SELECT @messageModel = REPLACE(@messageModel, '#cmsplayeridunmasked#', @cmsplayeridunmasked)
    SELECT @messageModel = REPLACE(@messageModel, '#PlayerLevelDescription#', @PlayerLevelDescription)
    SELECT @messageModel = REPLACE(@messageModel, '#offerdescription#', @offerdescription)
    SELECT @messageModel = REPLACE(@messageModel, '#timeawarded#', @timeawarded)

    IF ISNULL(@consumerMobile, '00') = '00'
        SELECT @messageModel = '\nPLEASE NOTE:MEMBER HAS NO VALID MOBILE\n' + @messageModel

    IF LEFT(@destinationNumber, 2) = '04'
        SELECT @destinationNumber = '+61' + RIGHT(@destinationNumber, LEN(@destinationNumber) - 1)

    IF ISNULL(@playeroffers_smsid, 0) > 0
    BEGIN
        UPDATE [SMSGateway].[PlayerOffers_SMS]
        SET InTransmission = 1,
            SubmittedToHostSMS = 1,
            SubmittedToHostSMSDateTime = GETDATE()
        WHERE PlayerOffers_SMSID = @playeroffers_smsid AND VenueID = @VenueID

        IF LEN(ISNULL(@destinationNumber, '+614')) > 4
        BEGIN
            INSERT INTO [SMSGateway].[Message_Body_Audit_Log]
                   ([VenueID], [ReferenceDescription], [TextMessageSource], [UserID], [HostID],
                    [TextMessageMergedContent], [DestinationNumber], [TransmissionTime], [Message_ID], [SubSystemSource])
            SELECT @VenueID, @ReferenceDescription, @messageHeader, @userID, @hostID,
                   @messageModel, @destinationNumber, GETDATE(), NULL, 'BONUS'

            SELECT @playeroffers_smsid AS id,
                   @VenueID           AS venue_id,
                   @messageHeader     AS source_number,
                   @destinationNumber AS dest_number,
                   @messageModel      AS content
        END
    END
END
