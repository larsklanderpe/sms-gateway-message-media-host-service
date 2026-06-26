-- ============================================================
-- SP:      SMSGateway.PE_GET_NEXT_BONUS_AWARD_MM_V2
-- Created: 2026-06-23
-- ============================================================
-- History:
--   2026-06-23 | LMDTS-64 two-phase delivery: claim only (InTransmission=1),
--              | SubmittedToHostSMS=1 deferred to PE_CONFIRM_SENT_BONUS_AWARD_MM.
--              | V1 (PE_GET_NEXT_BONUS_AWARD_MM) retained for rollback compatibility.
-- ============================================================
-- PURPOSE:
--   Claim phase of two-phase delivery. Marks InTransmission=1 and records the
--   claim timestamp (SubmittedToHostSMSDateTime), then returns the ready-to-send
--   message. Does NOT set SubmittedToHostSMS=1 -- that is set by
--   PE_CONFIRM_SENT_BONUS_AWARD_MM after HTTP 202 from MessageMedia. On failure
--   PE_RESET_FAILED_BONUS_AWARD_MM clears InTransmission and SubmittedToHostSMSDateTime.
--
-- PE HOST GUARD NOTE:
--   The Guard checks InTransmission=1 AND SubmittedToHostSMSDateTime > day_start().
--   Both are still set at claim time, so Guard behaviour is preserved. A reset
--   (failed send) clears SubmittedToHostSMSDateTime so the retry is permitted.
--
-- OUTPUT COLUMNS (standardised across all three feeds -- identical to V1):
--   id             INT           -- PlayerOffers_SMSID
--   venue_id       INT
--   source_number  VARCHAR(11)   -- TextMessageSource (sender ID)
--   dest_number    VARCHAR(25)   -- HostMobile formatted to +61
--   content        VARCHAR(1024) -- TextMessageBody with tokens merged
-- ============================================================

CREATE OR ALTER PROCEDURE [SMSGateway].[PE_GET_NEXT_BONUS_AWARD_MM_V2]
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
        -- LMDTS-64: claim only -- SubmittedToHostSMS=1 set by PE_CONFIRM_SENT_BONUS_AWARD_MM
        UPDATE [SMSGateway].[PlayerOffers_SMS]
        SET InTransmission = 1,
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
