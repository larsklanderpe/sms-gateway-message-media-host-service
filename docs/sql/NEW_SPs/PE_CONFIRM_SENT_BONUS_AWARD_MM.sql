-- ============================================================
-- SP:      SMSGateway.PE_CONFIRM_SENT_BONUS_AWARD_MM
-- Created: 2026-06-23
-- ============================================================
-- History:
--   2026-06-23 | LMDTS-64: confirm phase of two-phase delivery.
-- ============================================================
-- PURPOSE:
--   Called by the BonusAward SmsWorker after receiving HTTP 202 from MessageMedia.
--   Sets SubmittedToHostSMS=1, completing the two-phase delivery state.
--   Only updates records that are still InTransmission=1 and not yet confirmed,
--   preventing double-confirmation if called more than once.
--
--   NOTE: InTransmission=1 intentionally left in place after confirm. The PE Host
--   Guard reads InTransmission=1 AND SubmittedToHostSMSDateTime > day_start() to
--   prevent a second bonus SMS to the same PE host venue in the same day. Leaving
--   InTransmission=1 after confirm preserves this safeguard.
-- ============================================================

CREATE OR ALTER PROCEDURE [SMSGateway].[PE_CONFIRM_SENT_BONUS_AWARD_MM]
    @id       INT,
    @venue_id INT
AS
BEGIN
    SET NOCOUNT ON

    UPDATE [SMSGateway].[PlayerOffers_SMS]
    SET SubmittedToHostSMS = 1
    WHERE PlayerOffers_SMSID = @id
      AND VenueID = @venue_id
      AND InTransmission = 1
      AND SubmittedToHostSMS = 0
END
