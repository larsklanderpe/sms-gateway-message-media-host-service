-- ============================================================
-- SP:      SMSGateway.PE_RESET_FAILED_BONUS_AWARD_MM
-- Created: 2026-06-23
-- ============================================================
-- History:
--   2026-06-23 | LMDTS-64: failure reset for two-phase delivery.
-- ============================================================
-- PURPOSE:
--   Called by the BonusAward SmsWorker when MessageMedia returns a non-202
--   response or when SendAsync throws (network failure, timeout, etc.).
--   Clears InTransmission and SubmittedToHostSMSDateTime so the record
--   re-enters the queue on the next poll cycle.
--   Safety guard: only resets records not yet confirmed (SubmittedToHostSMS=0).
--
--   NOTE: Clearing SubmittedToHostSMSDateTime also releases the PE Host Guard
--   for this record, permitting a retry to the same PE host venue on the same day.
--   This is intentional -- a failed send should not consume the daily Guard slot.
-- ============================================================

CREATE OR ALTER PROCEDURE [SMSGateway].[PE_RESET_FAILED_BONUS_AWARD_MM]
    @id       INT,
    @venue_id INT
AS
BEGIN
    SET NOCOUNT ON

    UPDATE [SMSGateway].[PlayerOffers_SMS]
    SET InTransmission = 0,
        SubmittedToHostSMSDateTime = NULL
    WHERE PlayerOffers_SMSID = @id
      AND VenueID = @venue_id
      AND InTransmission = 1
      AND SubmittedToHostSMS = 0
END
