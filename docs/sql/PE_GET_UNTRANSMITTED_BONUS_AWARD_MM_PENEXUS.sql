-- ============================================================
-- SP:      SMSGateway.PE_GET_UNTRANSMITTED_BONUS_AWARD_MM
-- Source:  PE_Barrel_Cloud_Master (PENEXUS)
-- Captured: 2026-06-23
-- ============================================================
-- History:
--   2026-06-23 | Captured from PENEXUS for analysis / rewrite reference
-- ============================================================
-- OUTPUT COLUMNS (final SELECT — same as PEAUS):
--   playeroffers_smsid  int
--   VenueID             int
--   source_number       varchar(11)
--   destination_number  varchar(25)
--   content             varchar(1024)
--
-- DIFFERENCES vs PEAUS:
--   - No PE Host Guard block in this version
--   - VenueID update WHERE clause: NEXUS omits VenueID filter on the update
--   - Minor differences in suppression logic
-- ============================================================

CREATE   PROCEDURE [SMSGateway].[PE_GET_UNTRANSMITTED_BONUS_AWARD_MM]
WITH RECOMPILE
AS
    DECLARE @playeroffers_smsid INT
    DECLARE @venueid INT

    IF EXISTS (SELECT * FROM [SMSGateway].[NewMember_Host_SMS] WHERE iseligibleforsms = 1 AND ISNULL(intransmission, 0) = 0 AND ISNULL(SubmittedToHostSMS, 0) = 0)
    BEGIN
        EXEC [SMSGateway].[GET_UNTRANSMITTED_NEW_MEMBER_MM]
        PRINT 'NEW MEMBER'
        RETURN
    END

    IF EXISTS (SELECT * FROM [SMSGateway].[TierUpgrades_Host_SMS] WHERE iseligibleforsms = 1 AND ISNULL(intransmission, 0) = 0)
    BEGIN
        EXEC [SMSGateway].[GET_UNTRANSMITTED_TIER_UPGRADE_MM]
        PRINT 'TIERUPGRADE'
        RETURN
    END

    SELECT @playeroffers_smsid = posms.PlayerOffers_SMSID, @VenueID = posms.VenueID
    FROM [SMSGateway].PlayerOffers_SMS posms
    INNER JOIN (
        SELECT TOP 1 PlayerOffers_SMSID, VenueID
        FROM [SMSGateway].PlayerOffers_SMS
        WHERE submittedtoHostSMS = 0
          AND SubmittedToHostSMSDateTime IS NULL
          AND ISNULL(InTransmission, 0) = 0
          AND ISNULL(SuppressedFromTransmission, 0) = 0
        ORDER BY OfferAwardedDateTime
    ) tp ON posms.PlayerOffers_SMSID = tp.PlayerOffers_SMSID AND posms.venueid = tp.venueid

    DECLARE @shortname VARCHAR(255), @cmsplayerid VARCHAR(10), @cmsplayeridunmasked VARCHAR(10)
    DECLARE @ReferenceDescription VARCHAR(255), @userID VARCHAR(25), @hostID VARCHAR(10)
    DECLARE @firstname VARCHAR(255), @Surname VARCHAR(255), @lastname VARCHAR(255)
    DECLARE @memberbadge BIGINT
    DECLARE @PlayerLevelDescription VARCHAR(255), @OfferDescription VARCHAR(255), @timeAwarded VARCHAR(255)
    DECLARE @destinationNumber VARCHAR(25), @consumerMobile VARCHAR(25)
    DECLARE @messageModel VARCHAR(1024), @messageHeader VARCHAR(11)

    IF NOT EXISTS (
        SELECT * FROM [SMSGateway].PlayerOffers_SMS pos
        INNER JOIN [SMSGateway].[Message_Body_Model] mbm ON pos.ThirdPartyHostPromotionID = mbm.thirdpartypromotionid AND pos.VenueID = mbm.VenueID
        INNER JOIN [SMSGateway].[ThirdPartySMSIDS] tps ON pos.ThirdPartyHostID = tps.HostThirdPartyID AND pos.VenueID = tps.VenueID
        WHERE PlayerOffers_SMSID = @PlayerOffers_SMSID AND pos.VenueID = @VenueID
          AND HostSMSActive = 1 AND ISNULL(SuppressedFromTransmission, 0) = 0
    )
    BEGIN
        RETURN
    END

    SELECT @cmsplayerid = 'xxxx' + RIGHT(CMSPlayerID, 3),
           @memberbadge = CONVERT(BIGINT, cmsplayerid),
           @cmsplayeridunmasked = CONVERT(VARCHAR(8), CONVERT(BIGINT, cmsplayerid)),
           @shortName = FirstName + ' ' + LEFT(LastName, 1) + '.',
           @FirstName = FirstName, @surname = LastName, @LastName = LastName,
           @userID = @venueid + cmsplayerid + playeraccountnum,
           @destinationNumber = HostMobile, @consumerMobile = PlayerMobile,
           @PlayerLevelDescription = PlayerLevelDescription, @OfferDescription = OfferDescription,
           @timeAwarded = OfferAwardedDateTime, @hostID = tps.HostThirdPartyID,
           @ReferenceDescription = PromotionReference,
           @messageModel = TextMessageBody, @messageHeader = TextMessageSource
    FROM [SMSGateway].PlayerOffers_SMS pos
    INNER JOIN [SMSGateway].[Message_Body_Model] mbm ON pos.ThirdPartyHostPromotionID = mbm.thirdpartypromotionid AND pos.VenueID = mbm.VenueID
    INNER JOIN [SMSGateway].[ThirdPartySMSIDS] tps ON pos.ThirdPartyHostID = tps.HostThirdPartyID AND pos.VenueID = tps.VenueID
    WHERE PlayerOffers_SMSID = @PlayerOffers_SMSID AND pos.VenueID = @VenueID
      AND HostSMSActive = 1 AND ISNULL(SuppressedFromTransmission, 0) = 0

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
        UPDATE [SMSGateway].playerOffers_SMS
        SET intransmission = 1, SubmittedToHostSMS = 1, SubmittedToHostSMSDateTime = GETDATE()
        WHERE playeroffers_smsid = @playeroffers_smsid  -- NOTE: NEXUS omits VenueID here (PEAUS includes it)

        IF LEN(ISNULL(@destinationNumber, '+614')) > 4
        BEGIN
            INSERT INTO [SMSGateway].[Message_Body_Audit_Log]
                   ([VenueID], [ReferenceDescription], [TextMessageSource], [UserID], [HostID],
                    [TextMessageMergedContent], [DestinationNumber], [TransmissionTime], [Message_ID], [SubSystemSource])
            SELECT @VenueID, @ReferenceDescription, @messageHeader, @userID, @hostID,
                   @messageModel, @destinationNumber, GETDATE(), NULL, 'BONUS'

            SELECT @playeroffers_smsid AS playeroffers_smsid,
                   @VenueID AS VenueID,
                   @messageHeader AS source_number,
                   @destinationNumber AS destination_number,
                   @messageModel AS content
        END
    END
