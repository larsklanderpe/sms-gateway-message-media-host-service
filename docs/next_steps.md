# Next Steps — sms-gateway-message-media-host-service
_Last updated: 2026-06-23_

## Current state

LMDTS-64 (two-phase delivery confirmation) is implemented and on PR #2.
LMDTS-63 runtime fixes are on main (merged via PR #1).

## Deploy Order for LMDTS-64

### 1. DB (barrel — `PE_Barrel_Cloud_Master` / UAT `101.0.69.158`)

Run each of the following in `docs/sql/NEW_SPs/` — all use `CREATE OR ALTER` and are safe to re-run:

```
PE_GET_NEXT_NEW_MEMBER_MM_V2.sql
PE_GET_NEXT_TIER_UPGRADE_MM_V2.sql
PE_GET_NEXT_BONUS_AWARD_MM_V2.sql
PE_CONFIRM_SENT_NEW_MEMBER_MM.sql
PE_CONFIRM_SENT_TIER_UPGRADE_MM.sql
PE_CONFIRM_SENT_BONUS_AWARD_MM.sql
PE_RESET_FAILED_NEW_MEMBER_MM.sql
PE_RESET_FAILED_TIER_UPGRADE_MM.sql
PE_RESET_FAILED_BONUS_AWARD_MM.sql
PE_REAP_STUCK_NEW_MEMBER_MM.sql
PE_REAP_STUCK_TIER_UPGRADE_MM.sql
PE_REAP_STUCK_BONUS_AWARD_MM.sql
```

The V1 SPs (`PE_GET_NEXT_*_MM`) are untouched. Rollback = redeploy old binary only.

### 2. App

Merge PR #2, build/publish the project, stop the Windows service `SMS Gateway MessageMedia`,
deploy the new binary, start it.

### 3. Config

No new config keys required in `C:\peservices\configs\appsettings-SMSGMM.json`.
The new keys (`ReaperCutoffMinutes`, `ReaperIntervalPolls`) default correctly from `appsettings.json`.

## Verification Steps

- Startup log shows all three workers: `NewMember worker started`, `TierUpgrade worker started`, `BonusAward worker started`.
- On a real BonusAward send: log shows `BonusAward: confirmed id=... venue=... message_id=<uuid>`.
- Record has `SubmittedToHostSMS=1` in the DB after confirm.
- On simulated failure (set a bad API key temporarily): log shows `rejected ... reset for retry`. Record returns to `InTransmission=0` within one poll cycle (10s).
- After ~60s: log shows `reaper ran (cutoff=10m)` for each feed (requires Debug log level).

## Rollback

Redeploy the previous binary. No SP changes required — V1 SPs are still in place.

## Open Follow-ups

- [ ] **`message_id` in audit log** — run `EXEC sp_help 'SMSGateway.Message_Body_Audit_Log'` on UAT
  to get the PK column name, then add Confirm SP update of `Message_ID` column (deferred from LMDTS-64).
- [ ] **LMDTS-65** — test project, worker-registration regression test, failure-case harness.
- [ ] **Rotate compromised MessageMedia token** — key `UgCJZEjREUJgQGuXOsyf` hardcoded in legacy repo.
- [ ] **Do NOT deploy to production** until verified in TEST. Production still runs the legacy build.
