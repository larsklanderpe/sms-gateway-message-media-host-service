-- ============================================================
-- SP:      SMSGateway.PE_CHECK_NEW_MEMBER_QUEUE_MM
-- Created: 2026-06-22
-- ============================================================
-- History:
--   2026-06-22 | Written for sms-gateway-message-media-host-service build 6.6.x.x
-- ============================================================
-- PURPOSE:
--   Lightweight check for the NewMember feed only. No data mutations except
--   age-based suppression. Returns 1 row if a pending record is ready to
--   transmit, 0 rows if the queue is empty or everything is suppressed.
--
--   Called every 10 seconds by the NewMember SmsWorker. If this returns a
--   row, the worker then calls PE_GET_NEXT_NEW_MEMBER_MM.
--
-- SAFEGUARDS (all from PEAUS version, applied to NewMember only):
--   1. Deactivate records where HostSMSActiveForNewMember = 0
--   2. Age suppression: records older than 1 hour are suppressed
--   3. PE Host Guard: if a PE host already has InTransmission=1 today, suppress
--      remaining records for that host/venue to avoid duplicates
-- ============================================================

-- ============================================================
-- RENAME GATE
-- ============================================================
IF OBJECT_ID('[SMSGateway].[PE_CHECK_NEW_MEMBER_QUEUE_MM]') IS NOT NULL
BEGIN
    IF OBJECT_ID('[SMSGateway].[PE_CHECK_NEW_MEMBER_QUEUE_MM_BAK]') IS NOT NULL
        DROP PROCEDURE [SMSGateway].[PE_CHECK_NEW_MEMBER_QUEUE_MM_BAK]
    EXEC sp_rename '[SMSGateway].[PE_CHECK_NEW_MEMBER_QUEUE_MM]', 'PE_CHECK_NEW_MEMBER_QUEUE_MM_BAK', 'OBJECT'
END
GO

CREATE OR ALTER PROCEDURE [SMSGateway].[PE_CHECK_NEW_MEMBER_QUEUE_MM]
AS
BEGIN
    SET NOCOUNT ON

    -- =====================================================================
    -- STEP 1: Deactivate records where host has SMS disabled for new members
    -- =====================================================================
    UPDATE pos
    SET IsEligibleForSMS = 0
    FROM [SMSGateway].[NewMember_Host_SMS] pos
    INNER JOIN [SMSGateway].[Message_Body_Model] mbm
        ON pos.[PlayerCommMessageID] = mbm.thirdpartypromotionid
    INNER JOIN [SMSGateway].[ThirdPartySMSIDS] tps
        ON pos.ThirdPartyHostID = tps.HostThirdPartyID
    WHERE HostSMSActiveForNewMember = 0
      AND pos.PlayerCommMessageType = 1
      AND pos.IsEligibleForSMS = 1

    -- =====================================================================
    -- STEP 2: Age suppression -- records older than 1 hour are too late
    -- =====================================================================
    IF EXISTS (
        SELECT 1 FROM [SMSGateway].[NewMember_Host_SMS]
        WHERE SubmittedToHostSMS = 0
          AND ISNULL(SuppressedFromTransmission, 0) = 0
          AND ImportTimestamp < DATEADD(HOUR, -1, GETDATE())
    )
    BEGIN
        UPDATE [SMSGateway].[NewMember_Host_SMS]
        SET SubmittedToHostSMS = 1,
            SuppressedFromTransmission = 1,
            SuppressedFromTransmissionDateTime = GETDATE()
        WHERE SubmittedToHostSMS = 0
          AND ISNULL(SuppressedFromTransmission, 0) = 0
          AND ImportTimestamp < DATEADD(HOUR, -1, GETDATE())
    END

    -- =====================================================================
    -- STEP 3: PE Host Guard -- suppress remaining if host already in-flight today
    -- =====================================================================
    DECLARE @VenueID INT, @ThirdPartyHostID VARCHAR(8)

    SELECT TOP 1 @VenueID = VenueID, @ThirdPartyHostID = ThirdPartyHostID
    FROM [SMSGateway].[NewMember_Host_SMS]
    WHERE IsEligibleForSMS = 1
      AND SubmittedToHostSMS = 0
      AND ISNULL(InTransmission, 0) = 0
      AND ISNULL(SuppressedFromTransmission, 0) = 0

    IF @VenueID IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1 FROM [SMSGateway].[ThirdPartySMSIDS]
            WHERE HostThirdPartyID = @ThirdPartyHostID
              AND ISNULL(ispehost, 0) = 1
              AND VenueID = @VenueID
        )
        BEGIN
            IF EXISTS (
                SELECT 1 FROM [SMSGateway].[NewMember_Host_SMS]
                WHERE VenueID = @VenueID
                  AND ThirdPartyHostID = @ThirdPartyHostID
                  AND InTransmission = 1
                  AND SubmittedToHostSMSDateTime > dbo.current_day_start(GETDATE())
                  AND ISNULL(SuppressedFromTransmission, 0) = 0
            )
            BEGIN
                UPDATE [SMSGateway].[NewMember_Host_SMS]
                SET IsEligibleForSMS = 0,
                    SubmittedToHostSMS = 0,
                    SubmittedToHostSMSDateTime = GETDATE(),
                    SuppressedFromTransmission = 1,
                    SuppressedFromTransmissionDateTime = GETDATE()
                WHERE VenueID = @VenueID
                  AND ThirdPartyHostID = @ThirdPartyHostID
                  AND ISNULL(InTransmission, 0) = 0
                  AND IsEligibleForSMS = 1
                  AND ImportTimestamp > DATEADD(DAY, -1, GETDATE())
                  AND ISNULL(SuppressedFromTransmission, 0) = 0
                  AND SuppressedFromTransmissionDateTime IS NULL
                RETURN
            END
        END
    END

    -- =====================================================================
    -- STEP 4: Return 1 row if anything is pending, 0 rows if empty
    -- =====================================================================
    SELECT TOP 1 1 AS HasPending
    FROM [SMSGateway].[NewMember_Host_SMS]
    WHERE IsEligibleForSMS = 1
      AND SubmittedToHostSMS = 0
      AND ISNULL(InTransmission, 0) = 0
      AND ISNULL(SuppressedFromTransmission, 0) = 0

END
