-- ============================================================
-- SP:      SMSGateway.PE_REAP_STUCK_TIER_UPGRADE_MM
-- Created: 2026-06-23
-- ============================================================
-- History:
--   2026-06-23 | LMDTS-64: reaper for orphaned InTransmission records.
-- ============================================================
-- PURPOSE:
--   Handles the service-crash-mid-flight case: if the service dies between the
--   Get SP commit and the Confirm SP call, a record is left with InTransmission=1
--   and SubmittedToHostSMS=0 indefinitely. The reaper resets those records so
--   they re-enter the queue on the next poll cycle.
--   Called periodically by each SmsWorker (every ReaperIntervalPolls cycles).
--   Replaces the manual reset step documented in docs/helpdesk.md.
--
-- PARAMETER:
--   @cutoff_minutes INT -- age threshold; records older than this are reset.
--                          Default recommendation: 10 minutes.
-- ============================================================

CREATE OR ALTER PROCEDURE [SMSGateway].[PE_REAP_STUCK_TIER_UPGRADE_MM]
    @cutoff_minutes INT = 10
AS
BEGIN
    SET NOCOUNT ON

    UPDATE [SMSGateway].[TierUpgrades_Host_SMS]
    SET InTransmission = 0,
        SubmittedToHostSMSDateTime = NULL
    WHERE InTransmission = 1
      AND SubmittedToHostSMS = 0
      AND ISNULL(SuppressedFromTransmission, 0) = 0
      AND SubmittedToHostSMSDateTime < DATEADD(MINUTE, -@cutoff_minutes, GETDATE())
END
