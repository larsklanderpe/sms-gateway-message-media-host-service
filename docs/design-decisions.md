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

## Two-phase delivery: claim then confirm (LMDTS-64)

**Decision:** The Get SPs (`PE_GET_NEXT_*_MM_V2`) only claim a record (`InTransmission=1`) and record the claim timestamp. A separate Confirm SP (`PE_CONFIRM_SENT_*_MM`) sets `SubmittedToHostSMS=1` only after HTTP 202 from MessageMedia. On any failure the Reset SP (`PE_RESET_FAILED_*_MM`) clears `InTransmission=0` so the record re-enters the queue.

**Why:** The original V1 Get SPs set `SubmittedToHostSMS=1` and `InTransmission=1` atomically at pull time. C# never wrote back the HTTP outcome. Any failure between the SP commit and a successful 202 (network down, bad creds, service crash mid-flight) left the record permanently flagged as sent with the message never delivered. The two-phase pattern makes delivery confirmation an explicit DB write, so failures are retried instead of silently lost.

**Rollback boundary:** V1 SPs (`PE_GET_NEXT_*_MM`) are untouched. Redeploying the old C# binary restores old behaviour with no SP changes required.

---

## Reaper for orphaned in-flight records (LMDTS-64)

**Decision:** A reaper SP (`PE_REAP_STUCK_*_MM`) runs every `ReaperIntervalPolls` poll cycles (default every 6 x 10s = 60s) per feed. It resets `InTransmission=1, SubmittedToHostSMS=0` records whose claim timestamp is older than `ReaperCutoffMinutes` (default 10 minutes).

**Why:** A service crash between the V2 Get SP commit and the Confirm SP call leaves a record in `InTransmission=1` indefinitely. Without the reaper, this requires a manual SQL reset (previously documented in helpdesk.md). The reaper automates that recovery and eliminates the manual step.

**Why per-feed instead of one central reaper service:** The reaper uses the same `ISmsWorkerStrategy` SP name pattern as the rest of the architecture. No additional DI registration is needed, and each feed is independent. The feed-specific WHERE clause is already scoped to one table.

---

## PE Host Guard preserved in V2 BonusAward Get SP (LMDTS-64)

**Decision:** `SubmittedToHostSMSDateTime` is still set at claim time in `PE_GET_NEXT_BONUS_AWARD_MM_V2` (not deferred to the Confirm SP). The Reset SP clears it on failure.

**Why:** The PE Host Guard checks `InTransmission=1 AND SubmittedToHostSMSDateTime > day_start()`. Both columns must be present at claim time for the guard to fire for in-flight records. Deferring `SubmittedToHostSMSDateTime` to confirm would mean a second BonusAward for the same PE host could be claimed while the first was still in-flight, bypassing the guard. Setting it at claim time preserves the one-per-host-per-day safeguard. Clearing it on reset means a genuinely failed send does not consume the daily slot.

---

## message_id logged to file only (LMDTS-64 MVP scope)

**Decision:** The `message_id` returned in the MessageMedia 202 response body is parsed and logged to the FileLogger at Normal level but not written to the DB (not stored in `Message_Body_Audit_Log.Message_ID`).

**Why:** Writing `message_id` to the audit log requires knowing the audit log table's PK column name to update the already-inserted row. That column name was not available at implementation time without DB access. Logging to file provides immediate traceability for ops use (search the log for `message_id=`) without requiring a schema lookup or additional SP. Storing `message_id` in the DB is deferred to a future pass once the audit log PK is confirmed.

---

## External config file for credentials

**Decision:** `C:\peservices\configs\appsettings-SMSGMM.json` holds all credentials. `appsettings.json` in the repo has placeholder values only.

**Why:** The old `App.config` embedded credentials directly, including a hardcoded MessageMedia Base64 auth token that was checked in to source control. That token is treated as compromised. PE standard is to never commit credentials.
