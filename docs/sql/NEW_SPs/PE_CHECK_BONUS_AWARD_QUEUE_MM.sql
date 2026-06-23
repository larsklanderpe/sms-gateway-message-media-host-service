-- ============================================================
-- SP:      SMSGateway.PE_CHECK_BONUS_AWARD_QUEUE_MM
-- Created: 2026-06-22
-- ============================================================
-- History:
--   2026-06-22 | Written for sms-gateway-message-media-host-service build 6.6.x.x
--   2026-06-23 | Wrapped Database Mail calls (Step 1 orphan email, Step 2 queue-depth
--              | check + email) in TRY/CATCH so an msdb permission/mail failure can no
--              | longer abort the SP and block the BonusAward queue. Needs the service
--              | login added to msdb DatabaseMailUserRole to actually send alerts.
-- ============================================================
-- PURPOSE:
--   Lightweight check for the BonusAward (PlayerOffers) feed only. No data
--   mutations except suppression and alerting. Returns 1 row if a pending
--   record is ready to transmit, 0 rows if the queue is empty.
--
--   Called every 10 seconds by the BonusAward SmsWorker. If this returns a
--   row, the worker then calls PE_GET_NEXT_BONUS_AWARD_MM.
--
-- SAFEGUARDS (full PEAUS set):
--   1. Orphaned record trap: records with missing host/promotion refs are
--      emailed to support and suppressed so they don't block the queue
--   2. Queue depth alert: if >100 records pending today, email support
--      (rate-limited to once per hour)
--   3. Age suppression: records older than 1 hour are suppressed
--   4. PE Host Guard: if a PE host already has InTransmission=1 today, suppress
--      remaining records for that host/venue
-- ============================================================

-- ============================================================
-- RENAME GATE
-- ============================================================
IF OBJECT_ID('[SMSGateway].[PE_CHECK_BONUS_AWARD_QUEUE_MM]') IS NOT NULL
BEGIN
    IF OBJECT_ID('[SMSGateway].[PE_CHECK_BONUS_AWARD_QUEUE_MM_BAK]') IS NOT NULL
        DROP PROCEDURE [SMSGateway].[PE_CHECK_BONUS_AWARD_QUEUE_MM_BAK]
    EXEC sp_rename '[SMSGateway].[PE_CHECK_BONUS_AWARD_QUEUE_MM]', 'PE_CHECK_BONUS_AWARD_QUEUE_MM_BAK', 'OBJECT'
END
GO

CREATE OR ALTER PROCEDURE [SMSGateway].[PE_CHECK_BONUS_AWARD_QUEUE_MM]
AS
BEGIN
    SET NOCOUNT ON

    -- =====================================================================
    -- STEP 1: Orphaned record trap
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
        DECLARE @orphanCount INT
        DECLARE @emailRecipients NVARCHAR(MAX)
        DECLARE @emailBody NVARCHAR(MAX)

        SELECT @orphanCount = COUNT(*)
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
        SET @emailBody = @emailBody + CAST(@orphanCount AS VARCHAR(10)) + ' record(s) with missing host or promotion references suppressed.' + CHAR(13) + CHAR(10)

        SELECT @emailBody = @emailBody +
            'PlayerOffers_SMSID: ' + ISNULL(CAST(pos.PlayerOffers_SMSID AS VARCHAR(20)), 'NULL') + CHAR(13) + CHAR(10) +
            'VenueID: ' + ISNULL(CAST(pos.VenueID AS VARCHAR(10)), 'NULL') + CHAR(13) + CHAR(10) +
            'ThirdPartyHostID: ' + ISNULL(pos.ThirdPartyHostID, 'NULL') + ' HostMatch: ' + ISNULL(tps.HostThirdPartyID, '*** NO MATCH ***') + CHAR(13) + CHAR(10) +
            'ThirdPartyHostPromoID: ' + ISNULL(pos.ThirdPartyHostPromotionID, 'NULL') + ' PromoMatch: ' + ISNULL(mbm.thirdpartypromotionid, '*** NO MATCH ***') + CHAR(13) + CHAR(10) +
            '----' + CHAR(13) + CHAR(10)
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
              tps.HostThirdPartyID IS NULL OR mbm.thirdpartypromotionid IS NULL
              OR pos.ThirdPartyHostID IS NULL OR pos.ThirdPartyHostPromotionID IS NULL
          )
        ORDER BY pos.OfferAwardedDateTime

        -- Alerting is best-effort: a Database Mail permission/config failure must not
        -- block suppression or the rest of the queue check below.
        BEGIN TRY
            EXEC msdb.dbo.sp_send_dbmail
                @recipients = @emailRecipients,
                @subject = 'SMS Gateway Alert - Orphaned Records Suppressed',
                @body = @emailBody,
                @body_format = 'TEXT',
                @profile_name = 'SQLServer'
        END TRY
        BEGIN CATCH
        END CATCH

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
              tps.HostThirdPartyID IS NULL OR mbm.thirdpartypromotionid IS NULL
              OR pos.ThirdPartyHostID IS NULL OR pos.ThirdPartyHostPromotionID IS NULL
          )
    END

    -- =====================================================================
    -- STEP 2: Queue depth alert (once per hour max)
    -- =====================================================================
    DECLARE @queueDepth INT
    SELECT @queueDepth = COUNT(*)
    FROM [SMSGateway].[PlayerOffers_SMS]
    WHERE OfferAwardedDateTime > dbo.current_day_start(GETDATE())
      AND SubmittedToHostSMS = 0
      AND ISNULL(SuppressedFromTransmission, 0) = 0

    -- Reading msdb.dbo.sysmail_sentitems requires Database Mail rights. If the service
    -- login lacks them, treat as "already alerted" so the check degrades to no-email
    -- rather than throwing and blocking the queue (see DatabaseMailUserRole grant script).
    DECLARE @recentlyAlerted BIT = 0
    BEGIN TRY
        IF EXISTS (
            SELECT 1 FROM msdb.dbo.sysmail_sentitems
            WHERE recipients LIKE '%@playerelite.com.au%'
              AND subject = 'SMS Gateway Alert - Queue Depth Exceeds Threshold'
              AND send_request_date > DATEADD(HOUR, -1, GETDATE())
        )
            SET @recentlyAlerted = 1
    END TRY
    BEGIN CATCH
        SET @recentlyAlerted = 1
    END CATCH

    IF @queueDepth > 100 AND @recentlyAlerted = 0
    BEGIN
        DECLARE @queueRecipients NVARCHAR(MAX)
        DECLARE @queueBody NVARCHAR(MAX)

        SELECT @queueRecipients = COALESCE(@queueRecipients + ';', '') + EmailName
        FROM [dbo].[Support_EmailList]
        WHERE UseForTechnicalNotifications = 1

        SET @queueBody = 'SMS Gateway - Queue Depth Alert' + CHAR(13) + CHAR(10)
        SET @queueBody = @queueBody + CONVERT(VARCHAR(25), GETDATE(), 120) + CHAR(13) + CHAR(10)
        SET @queueBody = @queueBody + CAST(@queueDepth AS VARCHAR(10)) + ' bonus award record(s) pending transmission today.' + CHAR(13) + CHAR(10)
        SET @queueBody = @queueBody + 'The SMS gateway service may be stalled or falling behind.' + CHAR(13) + CHAR(10)

        BEGIN TRY
            EXEC msdb.dbo.sp_send_dbmail
                @recipients = @queueRecipients,
                @subject = 'SMS Gateway Alert - Queue Depth Exceeds Threshold',
                @body = @queueBody,
                @body_format = 'TEXT',
                @profile_name = 'SQLServer'
        END TRY
        BEGIN CATCH
        END CATCH
    END

    -- =====================================================================
    -- STEP 3: Age suppression -- records older than 1 hour are too late
    -- =====================================================================
    IF EXISTS (
        SELECT 1 FROM [SMSGateway].[PlayerOffers_SMS]
        WHERE SubmittedToHostSMS = 0
          AND ISNULL(SuppressedFromTransmission, 0) = 0
          AND OfferAwardedDateTime < DATEADD(HOUR, -1, GETDATE())
    )
    BEGIN
        UPDATE [SMSGateway].[PlayerOffers_SMS]
        SET SubmittedToHostSMS = 1,
            SuppressedFromTransmission = 1,
            SuppressedFromTransmissionDateTime = GETDATE()
        WHERE SubmittedToHostSMS = 0
          AND ISNULL(SuppressedFromTransmission, 0) = 0
          AND OfferAwardedDateTime < DATEADD(HOUR, -1, GETDATE())
    END

    -- =====================================================================
    -- STEP 4: Return 1 row if anything is pending, 0 rows if empty
    -- =====================================================================
    SELECT TOP 1 1 AS HasPending
    FROM [SMSGateway].[PlayerOffers_SMS]
    WHERE ISNULL(SubmittedToHostSMS, 0) = 0
      AND SubmittedToHostSMSDateTime IS NULL
      AND ISNULL(InTransmission, 0) = 0
      AND ISNULL(SuppressedFromTransmission, 0) = 0

END
