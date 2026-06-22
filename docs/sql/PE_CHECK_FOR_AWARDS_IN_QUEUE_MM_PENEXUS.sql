-- ============================================================
-- SP:      SMSGateway.PE_CHECK_FOR_AWARDS_IN_QUEUE_MM
-- Source:  PE_Barrel_Cloud_Master (PENEXUS)
-- Captured: 2026-06-23
-- ============================================================
-- History:
--   2026-06-23 | Captured from PENEXUS for analysis / rewrite reference
-- ============================================================
-- DIFFERENCES vs PEAUS version:
--   - No orphaned record error trap
--   - No queue depth alert
--   - Age suppression logic differs slightly (NEXUS uses
--     UpgradeAwardedDateTime for TierUpgrade cutoff date check;
--     PEAUS uses current_day_start for same)
--   - NewMember final SELECT: NEXUS has SuppressedFromTransmission = 1
--     in WHERE (looks like a bug — should be 0)
-- ============================================================

CREATE PROCEDURE [SMSGateway].[PE_CHECK_FOR_AWARDS_IN_QUEUE_MM]
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @PlayerOffers_SMSID BIGINT
    DECLARE @TierUpgrades_SMSID BIGINT
    DECLARE @VenueID INT
    DECLARE @thirdpartyhostid VARCHAR(8)

    -- Deactivate NewMember records where host has SMS disabled
    IF EXISTS (
        SELECT * FROM [SMSGateway].[NewMember_Host_SMS] pos
        INNER JOIN [SMSGateway].[Message_Body_Model] mbm ON pos.[PlayerCommMessageID] = mbm.thirdpartypromotionid
        INNER JOIN [SMSGateway].[ThirdPartySMSIDS] tps ON pos.ThirdPartyHostID = tps.HostThirdPartyID
        WHERE HostSMSActiveForNewMember = 0 AND pos.PlayerCommMessageType = 1 AND POS.IsEligibleForSMS = 1
    )
    BEGIN
        UPDATE POS SET iseligibleforsms = 0
        FROM [SMSGateway].[NewMember_Host_SMS] pos
        INNER JOIN [SMSGateway].[Message_Body_Model] mbm ON pos.[PlayerCommMessageID] = mbm.thirdpartypromotionid
        INNER JOIN [SMSGateway].[ThirdPartySMSIDS] tps ON pos.ThirdPartyHostID = tps.HostThirdPartyID
        WHERE HostSMSActiveForNewMember = 0 AND pos.PlayerCommMessageType = 1 AND POS.IsEligibleForSMS = 1
    END

    -- New Member feed
    IF EXISTS (
        SELECT TOP 1 [NewMember_HostSMSID] FROM [SMSGateway].[NewMember_Host_SMS]
        WHERE iseligibleforsms = 1 AND submittedtoHostSMS = 0 AND ISNULL(InTransmission, 0) = 0
    )
    BEGIN
        SELECT TOP 1 @PlayerOffers_SMSID = [NewMember_HostSMSID], @VenueID = VenueID, @thirdpartyhostid = ThirdPartyHostID
        FROM [SMSGateway].[NewMember_Host_SMS]
        WHERE iseligibleforsms = 1 AND submittedtoHostSMS = 0 AND ISNULL(InTransmission, 0) = 0

        IF EXISTS (SELECT * FROM SMSGateway.ThirdPartySMSIDS WHERE HostThirdPartyID = @thirdpartyhostid AND ISNULL(ispehost, 0) = 1 AND VenueID = @VenueID)
        BEGIN
            IF EXISTS (
                SELECT * FROM [SMSGateway].[NewMember_Host_SMS] pos (NOLOCK)
                WHERE SubmittedToHostSMSDateTime > dbo.current_day_start(GETDATE())
                  AND VenueID = @venueID AND ThirdPartyHostID = @ThirdPartyHostID AND InTransmission = 1
                  AND ISNULL(SuppressedFromTransmission, 0) = 0
            )
            BEGIN
                UPDATE [SMSGateway].[NewMember_Host_SMS]
                SET IsEligibleForSMS = 0, SubmittedToHostSMS = 0, SubmittedToHostSMSDateTime = GETDATE(),
                    SuppressedFromTransmission = 1, SuppressedFromTransmissionDateTime = GETDATE()
                WHERE VenueID = @VenueID AND ThirdPartyHostID = @thirdpartyhostid AND ISNULL(InTransmission, 0) = 0
                  AND IsEligibleForSMS = 1 AND [ImportTimestamp] > DATEADD(D, -1, GETDATE())
                  AND ISNULL(SuppressedFromTransmission, 0) = 0 AND SuppressedFromTransmissionDateTime IS NULL
                RETURN
            END
        END

        -- NOTE: SuppressedFromTransmission = 1 in WHERE looks like a bug (should be 0)
        SELECT TOP 1 [NewMember_HostSMSID] AS PlayerOffers_SMSID, VenueID, PlayerAccountNum, CMSPlayerID,
               FirstName, LastName, PlayerMobile, 'New Member' AS PLayerLevelDescription,
               '' AS OfferDescription, '' AS ThirdPartyID, '' AS ThirdPartyPromotionID,
               ThirdPartyHostID, PlayerCommMessageID AS ThirdPartyHostPromotionID
        FROM [SMSGateway].[NewMember_Host_SMS] (NOLOCK)
        WHERE iseligibleforsms = 1 AND submittedtoHostSMS = 0
          AND ISNULL(InTransmission, 0) = 0
          AND ISNULL(SuppressedFromTransmission, 0) = 1  -- SUSPECTED BUG: should be = 0
        RETURN
    END

    -- Tier Upgrade feed
    IF EXISTS (
        SELECT TOP 1 [TierUpgrades_HostSMSID] FROM [SMSGateway].[TierUpgrades_Host_SMS] (NOLOCK)
        WHERE iseligibleforsms = 1 AND submittedtoHostSMS = 0 AND ISNULL(InTransmission, 0) = 0
    )
    BEGIN
        SELECT TOP 1 @TierUpgrades_SMSID = [TierUpgrades_HostSMSID], @VenueID = VenueID, @ThirdPartyHostID = ThirdPartyHostID
        FROM [SMSGateway].[TierUpgrades_Host_SMS] (NOLOCK)
        WHERE iseligibleforsms = 1 AND submittedtoHostSMS = 0 AND ISNULL(InTransmission, 0) = 0

        IF EXISTS (SELECT * FROM SMSGateway.ThirdPartySMSIDS WHERE HostThirdPartyID = @thirdpartyhostid AND ISNULL(ispehost, 0) = 1 AND VenueID = @VenueID)
        BEGIN
            IF EXISTS (
                SELECT * FROM [SMSGateway].[TierUpgrades_Host_SMS] pos (NOLOCK)
                WHERE [UpgradeAwardedDateTime] > dbo.current_day_start(GETDATE())  -- NEXUS uses UpgradeAwardedDateTime, PEAUS uses SubmittedToHostSMSDateTime
                  AND VenueID = @venueID AND ThirdPartyHostID = @ThirdPartyHostID AND InTransmission = 1
                  AND ISNULL(SuppressedFromTransmission, 0) = 0
            )
            BEGIN
                UPDATE [SMSGateway].[TierUpgrades_Host_SMS]
                SET IsEligibleForSMS = 0, SubmittedToHostSMS = 0, SubmittedToHostSMSDateTime = GETDATE(),
                    SuppressedFromTransmission = 1, SuppressedFromTransmissionDateTime = GETDATE()
                WHERE VenueID = @VenueID AND ThirdPartyHostID = @thirdpartyhostid AND InTransmission = 0
                  AND [UpgradeAwardedDateTime] > dbo.current_day_start(GETDATE())
                  AND ISNULL(SuppressedFromTransmission, 0) = 0
                RETURN
            END
        END

        SELECT TOP 1 [TierUpgrades_HostSMSID] AS PlayerOffers_SMSID, VenueID, PlayerAccountNum, CMSPlayerID,
               FirstName, LastName, PlayerMobile, NewTierName AS PLayerLevelDescription,
               '' AS OfferDescription, '' AS ThirdPartyID, '' AS ThirdPartyPromotionID,
               ThirdPartyHostID, PlayerCommMessageID AS ThirdPartyHostPromotionID
        FROM [SMSGateway].[TierUpgrades_Host_SMS] (NOLOCK)
        WHERE iseligibleforsms = 1 AND submittedtoHostSMS = 0
          AND ISNULL(InTransmission, 0) = 0 AND ISNULL(SuppressedFromTransmission, 0) = 0
        RETURN
    END

    -- Bonus Award feed (PlayerOffers_SMS)
    SELECT TOP 1 @PlayerOffers_SMSID = PlayerOffers_SMSID, @VenueID = VenueID, @ThirdPartyHostID = ThirdPartyHostID
    FROM [SMSGateway].PlayerOffers_SMS (NOLOCK)
    WHERE ISNULL(SubmittedToHostSMS, 0) = 0 AND SubmittedToHostSMSDateTime IS NULL
      AND ISNULL(InTransmission, 0) = 0 AND ISNULL(SuppressedFromTransmission, 0) = 0
    ORDER BY OfferAwardedDateTime

    IF NOT EXISTS (
        SELECT * FROM [SMSGateway].PlayerOffers_SMS pos (NOLOCK)
        INNER JOIN [SMSGateway].[Message_Body_Model] mbm (NOLOCK) ON pos.ThirdPartyHostPromotionID = mbm.thirdpartypromotionid AND pos.VenueID = mbm.VenueID
        INNER JOIN [SMSGateway].[ThirdPartySMSIDS] tps (NOLOCK) ON pos.ThirdPartyHostID = tps.HostThirdPartyID AND pos.VenueID = tps.VenueID
        WHERE PlayerOffers_SMSID = @PlayerOffers_SMSID AND pos.VenueID = @VenueID AND HostSMSActive = 1
    )
    BEGIN
        UPDATE [SMSGateway].PlayerOffers_SMS
        SET IsEligibleForSMS = 0, SubmittedToHostSMS = 0, SubmittedToHostSMSDateTime = GETDATE(), SuppressedFromTransmission = 1
        WHERE PlayerOffers_SMSID = @PlayerOffers_SMSID AND VenueID = @VenueID
        RETURN
    END

    IF EXISTS (SELECT * FROM SMSGateway.ThirdPartySMSIDS WHERE HostThirdPartyID = @thirdpartyhostid AND ISNULL(ispehost, 0) = 1 AND VenueID = @VenueID)
    BEGIN
        IF EXISTS (
            SELECT * FROM [SMSGateway].PlayerOffers_SMS pos (NOLOCK)
            WHERE OfferAwardedDateTime > dbo.current_day_start(GETDATE())  -- NEXUS uses OfferAwardedDateTime, PEAUS uses SubmittedToHostSMSDateTime
              AND VenueID = @venueID AND ThirdPartyHostID = @ThirdPartyHostID AND InTransmission = 1
              AND ISNULL(SuppressedFromTransmission, 0) = 0
        )
        BEGIN
            UPDATE [SMSGateway].PlayerOffers_SMS
            SET IsEligibleForSMS = 0, SubmittedToHostSMS = 0, SubmittedToHostSMSDateTime = GETDATE(),
                SuppressedFromTransmission = 1, SuppressedFromTransmissionDateTime = GETDATE()
            WHERE VenueID = @VenueID AND ThirdPartyHostID = @thirdpartyhostid AND InTransmission = 0
              AND OfferAwardedDateTime > dbo.current_day_start(GETDATE())
              AND ISNULL(SuppressedFromTransmission, 0) = 0
            RETURN
        END
    END

    SELECT TOP 1 PlayerOffers_SMSID, VenueID, PlayerAccountNum, CMSPlayerID, FirstName, LastName, PlayerMobile,
           PLayerLevelDescription, OfferDescription, ThirdPartyID, ThirdPartyPromotionID,
           ThirdPartyHostID, ThirdPartyHostPromotionID
    FROM [SMSGateway].PlayerOffers_SMS (NOLOCK)
    WHERE submittedtoCustomerSMS = 0
      AND ISNULL(InTransmission, 0) = 0 AND ISNULL(SuppressedFromTransmission, 0) = 0
    ORDER BY OfferAwardedDateTime

END
