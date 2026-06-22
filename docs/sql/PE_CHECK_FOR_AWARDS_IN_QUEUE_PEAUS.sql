-- ============================================================
-- SP:      SMSGateway.PE_CHECK_FOR_AWARDS_IN_QUEUE
-- Source:  PE_Barrel_Cloud_Master (PEAUS)
-- Captured: 2026-06-23
-- ============================================================
-- History:
--   2026-06-23 | Captured from PEAUS for analysis / rewrite reference
-- ============================================================
-- NOTE: This is the OLDER version without the PEAUS MM-specific
--       orphaned record trap and queue depth alerting.
--       See PE_CHECK_FOR_AWARDS_IN_QUEUE_MM for the newer version.
-- ============================================================

CREATE   PROCEDURE [SMSGateway].[PE_CHECK_FOR_AWARDS_IN_QUEUE]
AS
BEGIN
	set nocount on

	declare @PlayerOffers_SMSID bigint
	declare @TierUpgrades_SMSID bigint
	declare @VenueID int
	declare @thirdpartyhostid varchar(8)


	if exists (select * FROM [SMSGateway].[NewMember_Host_SMS] pos
				inner join [SMSGateway].[Message_Body_Model] mbm on pos.[PlayerCommMessageID] = mbm.thirdpartypromotionid
				inner join [SMSGateway].[ThirdPartySMSIDS] tps on pos.ThirdPartyHostID = tps.HostThirdPartyID
				WHERE	HostSMSActiveForNewMember = 0
						and pos.PlayerCommMessageType = 1
						AND POS.IsEligibleForSMS = 1)
	begin
		UPDATE POS
		set iseligibleforsms = 0
		FROM [SMSGateway].[NewMember_Host_SMS] pos
				inner join [SMSGateway].[Message_Body_Model] mbm on pos.[PlayerCommMessageID] = mbm.thirdpartypromotionid
				inner join [SMSGateway].[ThirdPartySMSIDS] tps on pos.ThirdPartyHostID = tps.HostThirdPartyID
				WHERE	HostSMSActiveForNewMember = 0
						and pos.PlayerCommMessageType = 1
						AND POS.IsEligibleForSMS = 1
	END


	if exists (	select top 1  [NewMember_HostSMSID]
				from	[SMSGateway].[NewMember_Host_SMS]
				where	iseligibleforsms = 1 and
						submittedtoHostSMS = 0 and
						IsNull(InTransmission, 0) = 0  and
						isnull(SuppressedFromTransmission, 0) = 0
				)
	BEGIN
			select top 1  @PlayerOffers_SMSID = [NewMember_HostSMSID],
						 @VenueID = VenueID, @thirdpartyhostid = ThirdPartyHostID
			from	[SMSGateway].[NewMember_Host_SMS]
			where	iseligibleforsms = 1 and
					submittedtoHostSMS = 0 and
					IsNull(InTransmission, 0) = 0


			if exists (select * from SMSGateway.ThirdPartySMSIDS where HostThirdPartyID = @thirdpartyhostid and IsNUll(ispehost,0) = 1 and VenueID = @VenueID)
			BEGIN
				if exists (select * from [SMSGateway].[NewMember_Host_SMS] pos (nolock)
							where SubmittedToHostSMSDateTime > dbo.current_day_start(getdate()) and
								VenueID = @venueID and ThirdPartyHostID = @ThirdPartyHostID and InTransmission = 1  and
								isnull(SuppressedFromTransmission, 0) = 0)
				begin
					update	[SMSGateway].[NewMember_Host_SMS]
					set		IsEligibleForSMS = 0,
							SubmittedToHostSMS = 0,
							SubmittedToHostSMSDateTime = getdate(),
							SuppressedFromTransmission = 1,
							SuppressedFromTransmissionDateTime = getdate()
					where	VenueID = @VenueID and ThirdPartyHostID = @thirdpartyhostid and IsNull(InTransmission,0) = 0 and IsEligibleForSMS = 1 and [ImportTimestamp] > dateadd(d,-1, getdate()) and isnull(SuppressedFromTransmission, 0) = 0 and SuppressedFromTransmissionDateTime is null
					return
				end
			END

			SELECT TOP 1 [NewMember_HostSMSID] as PlayerOffers_SMSID, VenueID, PlayerAccountNum, CMSPlayerID, FirstName, LastName, PlayerMobile, 'New Member' as PLayerLevelDescription,
			''  as OfferDescription,'' as ThirdPartyID, '' as ThirdPartyPromotionID, ThirdPartyHostID, PlayerCommMessageID as ThirdPartyHostPromotionID
			FROM [SMSGateway].[NewMember_Host_SMS] (nolock)
			WHERE	iseligibleforsms = 1 AND
					submittedtoHostSMS = 0 AND
				ISNULL(InTransmission, 0) = 0 and
				isnull(SuppressedFromTransmission, 0) = 0
			return
	END

	if exists (	select top 1  [TierUpgrades_HostSMSID]
				from	[SMSGateway].[TierUpgrades_Host_SMS] (nolock)
				where	iseligibleforsms = 1 and
						submittedtoHostSMS = 0 and
						IsNull(InTransmission, 0) = 0and
				isnull(SuppressedFromTransmission, 0) = 0
				)
	BEGIN
			select top 1  @TierUpgrades_SMSID = [TierUpgrades_HostSMSID],
						  @VenueID = VenueID, @ThirdPartyHostID = ThirdPartyHostID
			from	[SMSGateway].[TierUpgrades_Host_SMS] (nolock)
			where	iseligibleforsms = 1 and
					submittedtoHostSMS = 0 and
					IsNull(InTransmission, 0) = 0 and
				isnull(SuppressedFromTransmission, 0) = 0

			if exists (select * from SMSGateway.ThirdPartySMSIDS where HostThirdPartyID = @thirdpartyhostid and IsNUll(ispehost,0) = 1 and VenueID = @VenueID)
			BEGIN
				if exists (select * from [SMSGateway].[TierUpgrades_Host_SMS] pos  (nolock)
							where SubmittedToHostSMSDateTime > dbo.current_day_start(getdate()) and
								VenueID = @venueID and ThirdPartyHostID = @ThirdPartyHostID and InTransmission = 1  and
								isnull(SuppressedFromTransmission, 0) = 0)
				begin
					update	[SMSGateway].[TierUpgrades_Host_SMS]
					set		IsEligibleForSMS = 0,
							SubmittedToHostSMS = 0,
							SubmittedToHostSMSDateTime = getdate(),
							SuppressedFromTransmission = 1,
							SuppressedFromTransmissionDateTime = getdate()
					where	VenueID = @venueID and ThirdPartyHostID = @ThirdPartyHostID and isnull(InTransmission,0) = 0 and IsEligibleForSMS = 1 and
							[UpgradeAwardedDateTime] > dateadd(d,-1, getdate()) and isnull(SuppressedFromTransmission, 0) = 0 and SuppressedFromTransmissionDateTime is null
					return
				end
			END

			SELECT TOP 1 [TierUpgrades_HostSMSID] as PlayerOffers_SMSID, VenueID, PlayerAccountNum, CMSPlayerID, FirstName, LastName, PlayerMobile, NewTierName as PLayerLevelDescription,
			''  as OfferDescription,'' as ThirdPartyID, '' as ThirdPartyPromotionID, ThirdPartyHostID, PlayerCommMessageID as ThirdPartyHostPromotionID
			FROM [SMSGateway].[TierUpgrades_Host_SMS] (nolock)
			WHERE	iseligibleforsms = 1 AND
					submittedtoHostSMS = 0 AND
				ISNULL(InTransmission, 0) = 0 and
				isnull(SuppressedFromTransmission, 0) = 0
			return
	END

	SELECT top 1 @PlayerOffers_SMSID = PlayerOffers_SMSID, @VenueID = VenueID, @ThirdPartyHostID = ThirdPartyHostID
	FROM	[SMSGateway].PlayerOffers_SMS  (nolock)
	WHERE	IsNull(SubmittedToHostSMS,0) = 0 AND
			SubmittedToHostSMSDateTime is null and
			ISNULL(InTransmission, 0) = 0 and
			isnull(SuppressedFromTransmission, 0) = 0
	order by OfferAwardedDateTime

	if not exists (select * from [SMSGateway].PlayerOffers_SMS pos  (nolock)
			inner join [SMSGateway].[Message_Body_Model] mbm (nolock) on pos.ThirdPartyHostPromotionID = mbm.thirdpartypromotionid and pos.VenueID = mbm.VenueID
			inner join [SMSGateway].[ThirdPartySMSIDS] tps (nolock) on pos.ThirdPartyHostID = tps.HostThirdPartyID and pos.VenueID = tps.VenueID
		WHERE	PlayerOffers_SMSID = @PlayerOffers_SMSID
				and pos.VenueID = @VenueID
				and HostSMSActive = 1)
	BEGIN
		update	[SMSGateway].PlayerOffers_SMS
		set		IsEligibleForSMS = 0,
				SubmittedToHostSMS = 0,
				SubmittedToHostSMSDateTime = getdate(),
				SuppressedFromTransmission = 1
		where	PlayerOffers_SMSID = @PlayerOffers_SMSID
				and VenueID = @VenueID
		return
	end

	if exists (select * from SMSGateway.ThirdPartySMSIDS where HostThirdPartyID = @thirdpartyhostid and IsNUll(ispehost,0) = 1 and VenueID = @VenueID)
	BEGIN
		if exists (select * from [SMSGateway].PlayerOffers_SMS pos  (nolock)
					where SubmittedToHostSMSDateTime > dbo.current_day_start(getdate()) and
						VenueID = @venueID and ThirdPartyHostID = @ThirdPartyHostID and InTransmission = 1  and
						isnull(SuppressedFromTransmission, 0) = 0)
		begin
			update	[SMSGateway].PlayerOffers_SMS
			set		IsEligibleForSMS = 0,
					SubmittedToHostSMS = 0,
					SubmittedToHostSMSDateTime = getdate(),
					SuppressedFromTransmission = 1,
					SuppressedFromTransmissionDateTime = getdate()
			where	VenueID = @VenueID and ThirdPartyHostID = @thirdpartyhostid and InTransmission = 0 and IsEligibleForSMS = 1 and OfferAwardedDateTime > dateadd(d,-1, getdate()) and isnull(SuppressedFromTransmission, 0) = 0 and SuppressedFromTransmissionDateTime is null
			return
		end
	END

	SELECT TOP 1 PlayerOffers_SMSID, VenueID, PlayerAccountNum, CMSPlayerID, FirstName, LastName, PlayerMobile, PLayerLevelDescription, OfferDescription,
	ThirdPartyID, ThirdPartyPromotionID, ThirdPartyHostID, ThirdPartyHostPromotionID
	FROM [SMSGateway].PlayerOffers_SMS  (nolock)
	WHERE	submittedtoCustomerSMS = 0 AND
			ISNULL(InTransmission, 0) = 0 and
			isnull(SuppressedFromTransmission, 0) = 0
	order by OfferAwardedDateTime

END
