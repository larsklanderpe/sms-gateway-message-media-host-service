# Session Notes — SMS Gateway MessageMedia Host Service

## CURRENT BRANCH: feature/LMDTS-64-delivery-confirmation

**Jira:** [LMDTS-63](https://playerelite.atlassian.net/browse/LMDTS-63)
**Service abbreviation:** SMSGMM
**Config file:** `C:\peservices\configs\appsettings-SMSGMM.json`
**Log path:** `C:\Logs\SMSGMM\SMSGMM_Log_MM-DD-YYYY.txt`

---

## OPEN PRs: PR #2 (feature/LMDTS-64-delivery-confirmation → main) — raised this session, pending merge

## EXTERNAL DEPENDENCIES
- `101.0.69.158` — UAT barrel DB (PEBarrel). Required for log level reads and all SP calls.
- `Configuration.Services_Logging` rows must exist for `SmsGatewayMM / SMSGMM_NewMember`, `SMSGMM_TierUpgrade`, `SMSGMM_BonusAward` before first run.
- MessageMedia REST API — **need fresh credentials**. Old hardcoded Base64 token in legacy source is COMPROMISED.

---

## Session 2026-06-23 (2) — LMDTS-64 two-phase delivery confirmation

**Tool:** Claude Code
**Branch:** feature/LMDTS-64-delivery-confirmation
**STATUS:** Code complete, build clean at 6.6.18.0. PR raised. SPs not yet deployed to UAT/TEST.

### Changed

**SQL — 12 new files in `docs/sql/NEW_SPs/`:**
- `PE_GET_NEXT_*_MM_V2.sql` (x3) — claim-only V2 Get SPs; V1 originals untouched (rollback = redeploy old binary, no SP changes)
- `PE_CONFIRM_SENT_*_MM.sql` (x3) — sets `SubmittedToHostSMS=1` after HTTP 202
- `PE_RESET_FAILED_*_MM.sql` (x3) — clears `InTransmission=0` on failure so record retries
- `PE_REAP_STUCK_*_MM.sql` (x3) — resets orphaned in-flight records older than N minutes (replaces manual SQL reset in helpdesk)

**C#:**
- `SmsMmConfig.cs` — added `ReaperCutoffMinutes` (default 10), `ReaperIntervalPolls` (default 6)
- `appsettings.json` — added default values for new config keys
- `ISmsWorkerStrategy.cs` — added `ConfirmProcedure`, `ResetProcedure`, `ReaperProcedure`
- `*Strategy.cs` (x3) — `GetProcedure` now points to `_V2` SPs; 3 new properties implemented
- `SmsDataAccess.cs` — added `ConfirmSent`, `ResetFailed`, `RunReaper`
- `MessageMediaClient.cs` — parses `messages[0].message_id` from 202 response body; `SendResult` gains `MessageId`
- `SmsWorker.cs` — calls `ConfirmSent`/`ResetFailed` on each send result; reaper runs every `ReaperIntervalPolls` polls; exception path resets the claimed record

### Design decisions recorded
- Two-phase delivery (claim then confirm)
- Reaper for orphaned in-flight records
- PE Host Guard preserved in V2 BonusAward SP
- `message_id` logged to file only (audit log DB update deferred — need `Message_Body_Audit_Log` PK column name from UAT DB)

### Next
1. **Deploy SPs to UAT barrel:** run all 12 new SP files in `docs/sql/NEW_SPs/` (the 3 V2 Get SPs + 9 new SPs). V1 SPs are untouched.
2. **Deploy new binary to TEST:** stop service, publish, start, verify.
3. **Verify:** log shows `confirmed id=... message_id=...` on a real BonusAward send. Also confirm that on a simulated failure (bad API key) the log shows `reset for retry` and the record is back to `InTransmission=0` in the DB.
4. **Deferred:** verify `Message_Body_Audit_Log` PK column name (`EXEC sp_help 'SMSGateway.Message_Body_Audit_Log'` on UAT) to enable future `message_id` storage in audit log.
5. **LMDTS-65:** test project / regression harness (next session).

### Refs
- LMDTS-64 (this session) — PR #2 raised
- LMDTS-65 (backlog) — test project

---

## Session 2026-06-23 — Runtime debugging, fixes merged to main

**Tool:** Claude Code
**Branch:** main (fixes/LMDTS-63-runtime-bugfixes merged via PR #1, branch deleted)
**STATUS:** Active (rebuild not yet deployed/verified in test; production unaffected on legacy build)

### Changed
- `SmsGatewayMM/Program.cs` — register workers as `IHostedService` directly (`AddHostedService<T>` dedupes by implementation type via TryAddEnumerable, so only NewMember was starting); derive HTTP BaseAddress from scheme+host (config value contained the path, resolving to `/v1/v1/messages`)
- `SmsGatewayMM/Http/MessageMediaClient.cs` — send `source_number_type=ALPHANUMERIC` + `format=SMS` (alpha sender IDs were rejected); return `SendResult(Success, StatusCode, Body)`
- `SmsGatewayMM/Workers/SmsWorker.cs` — log HTTP status + body on rejected sends
- `docs/sql/NEW_SPs/PE_CHECK_BONUS_AWARD_QUEUE_MM.sql` — TRY/CATCH around `sp_send_dbmail` + `sysmail_sentitems` so an msdb permission failure cannot abort the SP / block the queue
- `docs/sql/GRANT_DatabaseMail_SmsGatewayMM.sql` — NEW: DatabaseMailUserRole grant for the service login (Option A; Lars handled)
- `docs/helpdesk.md` — corrected `Configuration.Services_Logging` table shape (ServiceID, SubsystemID, ModifiedDate); DB target `PE_Barrel_Cloud_Master`

### Next
- Deploy rebuilt exe to TEST, confirm `BonusAward: sent` / HTTP 202 from new instrumentation. Do NOT deploy to prod until verified.
- LMDTS-65: add test project, extract worker registration into a testable method, add the 3-worker regression test + failure-case harness (fresh context window).
- Optional: comment on LMDTS-63 linking PR #1.

### Refs
- LMDTS-63 (parent; runtime fixes) — PR #1 merged to main, merge commit `b6b9a71`
- LMDTS-64 (backlog) — mark-sent-before-delivery message-loss; status-check design comment added
- LMDTS-65 (backlog) — test project / regression test / failure-case harness
- PR: https://github.com/larsklanderpe/sms-gateway-message-media-host-service/pull/1

### Backlog
1. LMDTS-64 — confirm delivery before marking sent (capture `message_id`; pull GET status vs delivery-report webhook)
2. LMDTS-65 — test harness
3. Rotate compromised MessageMedia token (key `UgCJZEjREUJgQGuXOsyf`, hardcoded in legacy repo)

### EXTERNAL DEPENDENCIES
- Barrel DB (`PE_Barrel_Cloud_Master` / UAT `101.0.69.158`) — log levels + all SP calls
- MessageMedia REST API (`https://api.messagemedia.com`, Basic auth) — token compromised, rotate
- Database Mail (msdb) — service login added to `DatabaseMailUserRole` (Option A, handled)

### Learning
- **Branch hygiene:** I made code edits on `main` before branching; Lars caught it. Create the `fixes/`/`feature/` branch BEFORE the first edit, even mid-debugging. (CLAUDE.md already states this; reinforce.) → CLAUDE.md / userPreferences
- **`AddHostedService<T>` dedupes by implementation type** (TryAddEnumerable) — registering the same BackgroundService class N times silently keeps one. Use `AddSingleton<IHostedService>`. → technical note
- **MessageMedia:** alphanumeric sender IDs require `source_number_type=ALPHANUMERIC` or they are rejected; base URL must be host-only when the code appends the path. → technical note
- **Config drift:** the external config file overrode the (correct) repo placeholder with a bad base URL. Verify the running config, not just the committed placeholder. → technical note

---

## Session 2026-06-22 — SP Analysis + Architecture Design

### What was established

**Old repo (reference only, do not copy):**
`D:\vc-newpe-repos\SMSGatewayMessageMediaHostService` — .NET Framework 4.5, no git history, hardcoded credentials.

**New repo:** `D:\vc-newpe-repos\sms-gateway-message-media-host-service`
- Git initialized, feature branch created.
- Docs structure in place.
- All SPs captured to `docs/sql/`.
- Plan rewritten for three-feed architecture.
- No C# code written yet — gated on missing sub-SPs (see below).

### SP Analysis Summary

Three SMS feed tables:
| Feed | Table | Old SP dispatch |
|------|-------|----------------|
| New Member | `SMSGateway.NewMember_Host_SMS` | `GET_UNTRANSMITTED_NEW_MEMBER_MM` (sub-SP, not yet captured) |
| Tier Upgrade | `SMSGateway.TierUpgrades_Host_SMS` | `GET_UNTRANSMITTED_TIER_UPGRADE_MM` (sub-SP, not yet captured) |
| Bonus Award | `SMSGateway.PlayerOffers_SMS` | Inline in `PE_GET_UNTRANSMITTED_BONUS_AWARD_MM` |

**Root cause of starvation:** `PE_GET_UNTRANSMITTED_BONUS_AWARD_MM` dispatches in waterfall priority (NewMember → TierUpgrade → BonusAward). If NewMember queue is never empty, the other two feeds are permanently starved.

**PEAUS vs PENEXUS material differences:**
- PEAUS has orphaned record error trap (email + suppress), queue depth alert, age suppression for all three feeds.
- PENEXUS lacks orphaned trap and queue depth alert; age suppression logic uses different timestamp column for TierUpgrade and BonusAward.
- **PENEXUS BUG:** `PE_CHECK_FOR_AWARDS_IN_QUEUE_MM` NewMember final SELECT has `ISNULL(SuppressedFromTransmission, 0) = 1` — should be `= 0`. NewMember SMS is silently broken on NEXUS right now.
- PENEXUS `PE_GET_UNTRANSMITTED_BONUS_AWARD_MM` UPDATE omits `VenueID` in WHERE — could mark wrong venue's record.
- PEAUS has PE Host Guard (suppress if already sent to same PE host today); PENEXUS does not.

**Rewrite decision:** PENEXUS differences treated as bugs to normalise, not features to preserve. Both clouds get PEAUS-equivalent SP logic.

### Captured SPs (in docs/sql/)
- `PE_CHECK_FOR_AWARDS_IN_QUEUE_PEAUS.sql` ✓
- `PE_CHECK_FOR_AWARDS_IN_QUEUE_MM_PEAUS.sql` ✓
- `PE_GET_UNTRANSMITTED_BONUS_AWARD_MM_PEAUS.sql` ✓
- `PE_CHECK_FOR_AWARDS_IN_QUEUE_MM_PENEXUS.sql` ✓
- `PE_GET_UNTRANSMITTED_BONUS_AWARD_MM_PENEXUS.sql` ✓

### Missing SPs (BLOCKER for Task 10 — new per-feed SPs)
- `SMSGateway.GET_UNTRANSMITTED_NEW_MEMBER_MM` — PEAUS and PENEXUS versions
- `SMSGateway.GET_UNTRANSMITTED_TIER_UPGRADE_MM` — PEAUS and PENEXUS versions

These are called via `EXEC` inside `PE_GET_UNTRANSMITTED_BONUS_AWARD_MM`. Need them to understand token substitution, column names, and any PE Host Guard variants before writing the new per-feed Get SPs.

### Architecture decision
`ISmsWorkerStrategy` interface with three concrete implementations (NewMember, TierUpgrade, BonusAward). One generic `SmsWorker : BackgroundService` registered three times, each with a different strategy. All three workers poll the DB every 10 seconds independently — no waterfall, no starvation.

---

## Next Session — Start Here

1. **Lars provides** `GET_UNTRANSMITTED_NEW_MEMBER_MM` and `GET_UNTRANSMITTED_TIER_UPGRADE_MM` (both clouds).
2. Save them to `docs/sql/` as `GET_UNTRANSMITTED_NEW_MEMBER_MM_PEAUS.sql` etc.
3. Proceed from **Task 1** in the plan: `docs/superpowers/plans/2026-06-22-sms-gateway-mm-modernisation.md`
4. Tasks 1–9 (C# scaffold) can proceed in parallel with Task 10 (new SPs). The sub-SPs are only needed to finalize the column names for `SmsDataAccess.GetNext()` DTO mapping and to write the new Get SPs.
5. Get fresh MessageMedia credentials before Task 9 (Program.cs / appsettings-SMSGMM.json).
6. Verify `Configuration.Services_Logging` rows exist on UAT barrel before first test run.
