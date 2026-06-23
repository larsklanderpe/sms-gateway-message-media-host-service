-- ============================================================
-- SP:      SMSGateway.PE_CONFIRM_SENT_NEW_MEMBER_MM
-- Created: 2026-06-23
-- ============================================================
-- History:
--   2026-06-23 | LMDTS-64: confirm phase of two-phase delivery.
-- ============================================================
-- PURPOSE:
--   Called by the NewMember SmsWorker after receiving HTTP 202 from MessageMedia.
--   Sets SubmittedToHostSMS=1, completing the two-phase delivery state.
--   Only updates records that are still InTransmission=1 and not yet confirmed,
--   preventing double-confirmation if called more than once.
-- ============================================================

CREATE OR ALTER PROCEDURE [SMSGateway].[PE_CONFIRM_SENT_NEW_MEMBER_MM]
    @id       INT,
    @venue_id INT
AS
BEGIN
    SET NOCOUNT ON

    UPDATE [SMSGateway].[NewMember_Host_SMS]
    SET SubmittedToHostSMS = 1
    WHERE NewMember_HostSMSID = @id
      AND VenueID = @venue_id
      AND InTransmission = 1
      AND SubmittedToHostSMS = 0
END
