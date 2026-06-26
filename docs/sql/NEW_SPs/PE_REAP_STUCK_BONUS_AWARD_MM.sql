-- ============================================================
-- SP:      SMSGateway.PE_REAP_STUCK_BONUS_AWARD_MM
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
--   NOTE: Clearing SubmittedToHostSMSDateTime also releases the PE Host Guard for
--   reaped records, permitting a retry to the same PE host venue on the same day.
--   SuppressedFromTransmission=0 guard ensures suppressed orphan records (already
--   handled by the orphan trap) are not erroneously reset.
--
-- PARAMETER:
--   @cutoff_minutes INT -- age threshold; records older than this are reset.
--                          Default recommendation: 10 minutes.
-- ============================================================

CREATE OR ALTER PROCEDURE [SMSGateway].[PE_REAP_STUCK_BONUS_AWARD_MM]
    @cutoff_minutes INT = 10
AS
BEGIN
    SET NOCOUNT ON

    UPDATE [SMSGateway].[PlayerOffers_SMS]
    SET InTransmission = 0,
        SubmittedToHostSMSDateTime = NULL
    WHERE InTransmission = 1
      AND SubmittedToHostSMS = 0
      AND ISNULL(SuppressedFromTransmission, 0) = 0
      AND SubmittedToHostSMSDateTime < DATEADD(MINUTE, -@cutoff_minutes, GETDATE())
END
