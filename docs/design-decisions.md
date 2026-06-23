# Design Decisions

## Three independent workers replacing single waterfall dispatcher

**Decision:** Three `SmsWorker : BackgroundService` instances, one per feed (NewMember, TierUpgrade, BonusAward), each with its own `ISmsWorkerStrategy` defining the feed-specific check and get SPs.

**Why:** The original `PE_GET_UNTRANSMITTED_BONUS_AWARD_MM` dispatched all three feeds in waterfall priority order (NewMember checked first; if any existed, the SP returned without touching TierUpgrade or BonusAward). If the NewMember queue was never empty, TierUpgrade and BonusAward records were permanently starved. This was a known operational characteristic of the old service, not a deliberate business rule.

**Trade-off:** Three DB connections per poll cycle instead of one. At a 10-second interval and the volume of this service, this is not a concern.

---

## ISmsWorkerStrategy interface for extensibility

**Decision:** Feed identity (SP names, subsystem name, feed label) lives in a strategy class rather than being hardcoded in the worker.

**Why:** Adding a fourth or fifth feed in the future (e.g., a Salesforce journey trigger) requires only a new strategy class and a registration line in Program.cs. The worker loop, DB access, HTTP client, and logging are unchanged.

---

## TierUpgrade host-active guard added (behaviour change from old SP)

**Decision:** `PE_GET_NEXT_TIER_UPGRADE_MM` wraps the data SELECT in an `IF EXISTS` check for `HostSMSActiveForTiering = 1`, with an `ELSE` branch that sets `IsEligibleForSMS = 0`.

**Why:** The old `GET_UNTRANSMITTED_TIER_UPGRADE_MM` had no such guard. If the host was inactive for tiering, the data SELECT returned nothing (due to the `HostSMSActiveForTiering = 1` WHERE clause), but the subsequent `UPDATE ... SET InTransmission = 1` still ran, leaving the record marked as transmitted with no message actually sent. In the old single-threaded waterfall this was tolerable (the record just sat there and the waterfall moved on). With an independent TierUpgrade worker, a stuck InTransmission record would block the entire TierUpgrade queue on the next poll. The guard was added intentionally with the move to multi-threaded operation.

---

## PENEXUS differences treated as bugs to normalise

**Decision:** Both clouds (PEAUS and PENEXUS) get identical new SP logic, based on the more robust PEAUS version.

**Why:** The PENEXUS variants were missing the orphaned record trap, queue depth alert, and PE Host Guard (all present in PEAUS). The PENEXUS `PE_CHECK_FOR_AWARDS_IN_QUEUE_MM` also had a confirmed bug in the NewMember final SELECT (`SuppressedFromTransmission = 1` should be `= 0`), meaning NewMember SMS was silently non-functional on NEXUS. There is no identified business reason for NEXUS to have fewer safeguards than PEAUS.

---

## Standardised 5-column output from all Get SPs

**Decision:** All three Get SPs (`PE_GET_NEXT_NEW_MEMBER_MM`, `PE_GET_NEXT_TIER_UPGRADE_MM`, `PE_GET_NEXT_BONUS_AWARD_MM`) return: `id, venue_id, source_number, dest_number, content`.

**Why:** The old `GET_UNTRANSMITTED_TIER_UPGRADE_MM` returned only 4 columns -- it omitted `VenueID` even though the variable was populated. NewMember and BonusAward both returned it. Normalising to 5 columns allows `SmsDataAccess.GetNext()` to use identical Dapper mapping for all three feeds. `VenueID` is also needed for logging and any future per-venue routing logic.

---

## Named IHttpClientFactory client for MessageMedia

**Decision:** MessageMedia HTTP calls go through a named `IHttpClientFactory` client ("MessageMedia") registered in DI, not a `new HttpClient()` per call.

**Why:** The old service created a `new HttpClient()` per SMS send, which causes socket exhaustion under load (TIME_WAIT accumulation). The named client pattern reuses connections and is the .NET standard for this pattern.

---

## External config file for credentials

**Decision:** `C:\peservices\configs\appsettings-SMSGMM.json` holds all credentials. `appsettings.json` in the repo has placeholder values only.

**Why:** The old `App.config` embedded credentials directly, including a hardcoded MessageMedia Base64 auth token that was checked in to source control. That token is treated as compromised. PE standard is to never commit credentials.
