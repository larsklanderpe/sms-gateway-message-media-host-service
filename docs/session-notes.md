# Session Notes — SMS Gateway MessageMedia Host Service

## CURRENT BRANCH: feature/LMDTS-63-dotnet10-three-feed-modernisation

**Jira:** [LMDTS-63](https://playerelite.atlassian.net/browse/LMDTS-63)
**Service abbreviation:** SMSGMM
**Config file:** `C:\peservices\configs\appsettings-SMSGMM.json`
**Log path:** `C:\Logs\SMSGMM\SMSGMM_Log_MM-DD-YYYY.txt`

---

## OPEN PRs: None yet (not pushed to GitHub)

## EXTERNAL DEPENDENCIES
- `101.0.69.158` — UAT barrel DB (PEBarrel). Required for log level reads and all SP calls.
- `Configuration.Services_Logging` rows must exist for `SmsGatewayMM / SMSGMM_NewMember`, `SMSGMM_TierUpgrade`, `SMSGMM_BonusAward` before first run.
- MessageMedia REST API — **need fresh credentials**. Old hardcoded Base64 token in legacy source is COMPROMISED.

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
