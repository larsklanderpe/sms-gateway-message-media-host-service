-- ============================================================
-- SP:      SMSGateway.PE_CHECK_FOR_AWARDS_IN_QUEUE_MM
-- Source:  PE_Barrel_Cloud_Master (PEAUS)
-- Captured: 2026-06-23
-- ============================================================
-- History:
--   2026-06-23 | Captured from PEAUS for analysis / rewrite reference
-- ============================================================
-- NOTE: This is the more advanced PEAUS version. It includes:
--   1. Orphaned record error trap (email + suppress bad records)
--   2. Queue depth alert (email if >100 pending today)
--   3. Age-based suppression (records > 1 hour old suppressed)
-- The PENEXUS version (PE_CHECK_FOR_AWARDS_IN_QUEUE_MM_PENEXUS.sql)
-- lacks items 1 and 2 and handles age suppression differently.
-- ============================================================

CREATE PROCEDURE [SMSGateway].[PE_CHECK_FOR_AWARDS_IN_QUEUE_MM]
AS
BEGIN
    SET NOCOUNT ON

    -- =====================================================================
    -- ERROR TRAP: Detect orphaned records with missing host/promotion refs
    -- =====================================================================
    IF EXISTS (
        SELECT 1
        FROM [SMSGateway].[PlayerOffers_SMS] pos
        LEFT JOIN [SMSGateway].[ThirdPartySMSIDS] tps
            ON pos.ThirdPartyHostID = tps.HostThirdPartyID AND pos.VenueID = tps.VenueID
        LEFT JOIN [SMSGateway].[Message_Body_Model] mbm
            ON pos.ThirdPartyHostPromotionID = mbm.thirdpartypromotionid AND pos.VenueID = mbm.VenueID
        WHERE ISNULL(pos.SubmittedToHostSMS, 0) = 0
          AND pos.SubmittedToHostSMSDateTime IS NULL
          AND ISNULL(pos.InTransmission, 0) = 0
          AND ISNULL(pos.SuppressedFromTransmission, 0) = 0
          AND (
              tps.HostThirdPartyID IS NULL
              OR mbm.thirdpartypromotionid IS NULL
              OR pos.ThirdPartyHostID IS NULL
              OR pos.ThirdPartyHostPromotionID IS NULL
          )
    )
    BEGIN
        DECLARE @emailBody NVARCHAR(MAX)
        DECLARE @emailRecipients NVARCHAR(MAX)
        DECLARE @recordCount INT

        SELECT @recordCount = COUNT(*)
        FROM [SMSGateway].[PlayerOffers_SMS] pos
        LEFT JOIN [SMSGateway].[ThirdPartySMSIDS] tps
            ON pos.ThirdPartyHostID = tps.HostThirdPartyID AND pos.VenueID = tps.VenueID
        LEFT JOIN [SMSGateway].[Message_Body_Model] mbm
            ON pos.ThirdPartyHostPromotionID = mbm.thirdpartypromotionid AND pos.VenueID = mbm.VenueID
        WHERE ISNULL(pos.SubmittedToHostSMS, 0) = 0
          AND pos.SubmittedToHostSMSDateTime IS NULL
          AND ISNULL(pos.InTransmission, 0) = 0
          AND ISNULL(pos.SuppressedFromTransmission, 0) = 0
          AND (
              tps.HostThirdPartyID IS NULL
              OR mbm.thirdpartypromotionid IS NULL
              OR pos.ThirdPartyHostID IS NULL
              OR pos.ThirdPartyHostPromotionID IS NULL
          )

        SELECT @emailRecipients = COALESCE(@emailRecipients + ';', '') + EmailName
        FROM [dbo].[Support_EmailList]
        WHERE UseForTechnicalNotifications = 1

        SET @emailBody = 'SMS Gateway - Orphaned Queue Records Detected and Suppressed' + CHAR(13) + CHAR(10)
        SET @emailBody = @emailBody + '============================================================' + CHAR(13) + CHAR(10)
        SET @emailBody = @emailBody + CONVERT(VARCHAR(25), GETDATE(), 120) + CHAR(13) + CHAR(10)
        SET @emailBody = @emailBody + CAST(@recordCount AS VARCHAR(10)) + ' record(s) were found with missing host or promotion references and have been suppressed.' + CHAR(13) + CHAR(10)
        SET @emailBody = @emailBody + 'These records were blocking the SMS queue.' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
        SET @emailBody = @emailBody + 'RECORD DETAILS:' + CHAR(13) + CHAR(10)
        SET @emailBody = @emailBody + '------------------------------------------------------------' + CHAR(13) + CHAR(10)

        SELECT @emailBody = @emailBody +
            'PlayerOffers_SMSID : ' + ISNULL(CAST(pos.PlayerOffers_SMSID AS VARCHAR(20)), 'NULL') + CHAR(13) + CHAR(10) +
            'VenueID            : ' + ISNULL(CAST(pos.VenueID AS VARCHAR(10)), 'NULL') + CHAR(13) + CHAR(10) +
            'PlayerAccountNum   : ' + ISNULL(pos.PlayerAccountNum, 'NULL') + CHAR(13) + CHAR(10) +
            'ThirdPartyHostID   : ' + ISNULL(pos.ThirdPartyHostID, 'NULL') + CHAR(13) + CHAR(10) +
            'HostMatch          : ' + ISNULL(tps.HostThirdPartyID, '*** NO MATCH IN ThirdPartySMSIDS ***') + CHAR(13) + CHAR(10) +
            'ThirdPartyHostPromoID : ' + ISNULL(pos.ThirdPartyHostPromotionID, 'NULL') + CHAR(13) + CHAR(10) +
            'PromoMatch         : ' + ISNULL(mbm.thirdpartypromotionid, '*** NO MATCH IN Message_Body_Model ***') + CHAR(13) + CHAR(10) +
            'OfferAwardedDateTime: ' + ISNULL(CONVERT(VARCHAR(25), pos.OfferAwardedDateTime, 120), 'NULL') + CHAR(13) + CHAR(10) +
            'SyncedToCloudDateTime: ' + ISNULL(CONVERT(VARCHAR(25), pos.SyncedToCloudDateTime, 120), 'NULL') + CHAR(13) + CHAR(10) +
            '------------------------------------------------------------' + CHAR(13) + CHAR(10)
        FROM [SMSGateway].[PlayerOffers_SMS] pos
        LEFT JOIN [SMSGateway].[ThirdPartySMSIDS] tps
            ON pos.ThirdPartyHostID = tps.HostThirdPartyID AND pos.VenueID = tps.VenueID
        LEFT JOIN [SMSGateway].[Message_Body_Model] mbm
            ON pos.ThirdPartyHostPromotionID = mbm.thirdpartypromotionid AND pos.VenueID = mbm.VenueID
        WHERE ISNULL(pos.SubmittedToHostSMS, 0) = 0
          AND pos.SubmittedToHostSMSDateTime IS NULL
          AND ISNULL(pos.InTransmission, 0) = 0
          AND ISNULL(pos.SuppressedFromTransmission, 0) = 0
          AND (
              tps.HostThirdPartyID IS NULL
              OR mbm.thirdpartypromotionid IS NULL
              OR pos.ThirdPartyHostID IS NULL
              OR pos.ThirdPartyHostPromotionID IS NULL
          )
        ORDER BY pos.OfferAwardedDateTime

        EXEC msdb.dbo.sp_send_dbmail
            @recipients = @emailRecipients,
            @subject = 'SMS Gateway Alert - Orphaned Records Suppressed',
            @body = @emailBody,
            @body_format = 'TEXT',
            @profile_name = 'SQLServer'

        UPDATE pos
        SET SubmittedToHostSMS = 1,
            SubmittedToHostSMSDateTime = GETDATE(),
            SuppressedFromTransmission = 1,
            SuppressedFromTransmissionDateTime = GETDATE()
        FROM [SMSGateway].[PlayerOffers_SMS] pos
        LEFT JOIN [SMSGateway].[ThirdPartySMSIDS] tps
            ON pos.ThirdPartyHostID = tps.HostThirdPartyID AND pos.VenueID = tps.VenueID
        LEFT JOIN [SMSGateway].[Message_Body_Model] mbm
            ON pos.ThirdPartyHostPromotionID = mbm.thirdpartypromotionid AND pos.VenueID = mbm.VenueID
        WHERE ISNULL(pos.SubmittedToHostSMS, 0) = 0
          AND pos.SubmittedToHostSMSDateTime IS NULL
          AND ISNULL(pos.InTransmission, 0) = 0
          AND ISNULL(pos.SuppressedFromTransmission, 0) = 0
          AND (
              tps.HostThirdPartyID IS NULL
              OR mbm.thirdpartypromotionid IS NULL
              OR pos.ThirdPartyHostID IS NULL
              OR pos.ThirdPartyHostPromotionID IS NULL
          )
    END

    -- =====================================================================
    -- QUEUE DEPTH ALERT
    -- =====================================================================
    DECLARE @QueueDepth INT
    SELECT @QueueDepth = COUNT(*)
    FROM [SMSGateway].[PlayerOffers_SMS]
    WHERE OfferAwardedDateTime > dbo.current_day_start(GETDATE())
      AND SubmittedToHostSMS = 0
      AND SuppressedFromTransmission = 0

    IF @QueueDepth > 100 AND NOT EXISTS (
           SELECT 1 FROM msdb.dbo.sysmail_sentitems
           WHERE recipients LIKE '%@playerelite.com.au%'
             AND subject = 'SMS Gateway Alert - Queue Depth Exceeds Threshold'
             AND send_request_date > DATEADD(HOUR, -1, GETDATE())
       )
    BEGIN
        DECLARE @queueEmailBody NVARCHAR(MAX)
        DECLARE @queueEmailRecipients NVARCHAR(MAX)

        SELECT @queueEmailRecipients = COALESCE(@queueEmailRecipients + ';', '') + EmailName
        FROM [dbo].[Support_EmailList]
        WHERE UseForTechnicalNotifications = 1

        SET @queueEmailBody = 'SMS Gateway - Queue Depth Alert' + CHAR(13) + CHAR(10)
        SET @queueEmailBody = @queueEmailBody + '============================================================' + CHAR(13) + CHAR(10)
        SET @queueEmailBody = @queueEmailBody + CONVERT(VARCHAR(25), GETDATE(), 120) + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
        SET @queueEmailBody = @queueEmailBody + CAST(@QueueDepth AS VARCHAR(10)) + ' record(s) are currently pending transmission for today.' + CHAR(13) + CHAR(10)
        SET @queueEmailBody = @queueEmailBody + 'This may indicate the SMS gateway service is stalled or falling behind.' + CHAR(13) + CHAR(10)

        EXEC msdb.dbo.sp_send_dbmail
            @recipients = @queueEmailRecipients,
            @subject = 'SMS Gateway Alert - Queue Depth Exceeds Threshold',
            @body = @queueEmailBody,
            @body_format = 'TEXT',
            @profile_name = 'SQLServer'
    END

    -- =====================================================================
    -- AGE-BASED SUPPRESSION (> 1 hour old = too late to send)
    -- =====================================================================
    DECLARE @PlayerOffers_SMSID BIGINT
    DECLARE @TierUpgrades_SMSID BIGINT
    DECLARE @VenueID INT
    DECLARE @thirdpartyhostid VARCHAR(8)

    IF EXISTS (SELECT * FROM [SMSGateway].[NewMember_Host_SMS] WHERE SubmittedToHostSMS = 0 AND SuppressedFromTransmission = 0 AND ImportTimeStamp < DATEADD(HOUR, -1, GETDATE()))
    BEGIN
        UPDATE [SMSGateway].[NewMember_Host_SMS]
        SET SubmittedToHostSMS = 1, SuppressedFromTransmission = 1, SuppressedFromTransmissionDateTime = GETDATE()
        WHERE SubmittedToHostSMS = 0 AND SuppressedFromTransmission = 0 AND ImportTimeStamp < DATEADD(HOUR, -1, GETDATE())
    END

    IF EXISTS (SELECT * FROM [SMSGateway].[TierUpgrades_Host_SMS] WHERE SubmittedToHostSMS = 0 AND SuppressedFromTransmission = 0 AND UpgradeAwardedDateTime < DATEADD(HOUR, -1, GETDATE()))
    BEGIN
        UPDATE [SMSGateway].[TierUpgrades_Host_SMS]
        SET SubmittedToHostSMS = 1, SuppressedFromTransmission = 1, SuppressedFromTransmissionDateTime = GETDATE()
        WHERE SubmittedToHostSMS = 0 AND SuppressedFromTransmission = 0 AND UpgradeAwardedDateTime < DATEADD(HOUR, -1, GETDATE())
    END

    IF EXISTS (SELECT * FROM [SMSGateway].[PlayerOffers_SMS] WHERE SubmittedToHostSMS = 0 AND SuppressedFromTransmission = 0 AND OfferAwardedDateTime < DATEADD(HOUR, -1, GETDATE()))
    BEGIN
        UPDATE [SMSGateway].[PlayerOffers_SMS]
        SET SubmittedToHostSMS = 1, SuppressedFromTransmission = 1, SuppressedFromTransmissionDateTime = GETDATE()
        WHERE SubmittedToHostSMS = 0 AND SuppressedFromTransmission = 0 AND OfferAwardedDateTime < DATEADD(HOUR, -1, GETDATE())
    END

    IF EXISTS (SELECT * FROM [SMSGateway].[PlayerOffers_SMS] WHERE SubmittedToHostSMS = 0 AND SuppressedFromTransmission = 0 AND iseligibleforsms = 1 AND OfferAwardedDateTime IS NULL AND SyncedToCloudDateTime > DATEADD(D, -1, GETDATE()))
    BEGIN
        UPDATE [SMSGateway].[PlayerOffers_SMS]
        SET SubmittedToHostSMS = 1, SuppressedFromTransmission = 1, SuppressedFromTransmissionDateTime = GETDATE()
        WHERE SubmittedToHostSMS = 0 AND SuppressedFromTransmission = 0 AND iseligibleforsms = 1 AND OfferAwardedDateTime IS NULL AND SyncedToCloudDateTime > DATEADD(D, -1, GETDATE())
    END

    -- =====================================================================
    -- FEED PRIORITY: New Member → Tier Upgrade → Bonus Award (waterfall)
    -- NOTE: This priority ordering is the root cause of starvation.
    --       Rewrite will replace this with three independent feed SPs.
    -- =====================================================================

    -- [NewMember + TierUpgrade + BonusAward waterfall continues as in PENEXUS version...]
    -- (see PE_CHECK_FOR_AWARDS_IN_QUEUE_MM_PENEXUS.sql for the shared queue logic)

END
