# Deployment Runbook — LMDTS-64: Two-Phase Delivery Confirmation
_Date: 2026-06-23 | Branch: `feature/LMDTS-64-delivery-confirmation` | PR #2_

---

> **WARNING — LOG LEVEL IS DB-DRIVEN, NOT FILE-DRIVEN**
>
> This is a Windows Service. Log level is stored in `Configuration.Services_Logging`
> on `PE_Barrel_Cloud_Master` and read at runtime on every poll cycle.
> Editing `appsettings.json` does NOT change log level. Do not restart the service
> to change log level. Change the DB row instead (SQL in Step 0 below).

---

## Scope

Deploys the two-phase delivery confirmation fix. The service will now:
- Claim a record (`InTransmission=1`) at pull time via new V2 Get SPs
- Confirm delivery (`SubmittedToHostSMS=1`) only after HTTP 202 from MessageMedia
- Reset the claim automatically on failure so the record re-queues

**Rollback:** Redeploy the previous binary. No SP changes needed — V1 SPs are untouched.

---

## Step 0 — Pre-flight: verify DB rows and log level

Run against `PE_Barrel_Cloud_Master` (prod) or `PE_Barrel_UAT_260521` (UAT):

```sql
-- Verify log level rows exist (0=Normal, 1=Debug, 2=Verbose)
SELECT ServiceID, SubsystemID, LogLevel, ModifiedDate
FROM Configuration.Services_Logging
WHERE ServiceID = 'SmsGatewayMM'
ORDER BY SubsystemID;

-- Expected rows:
--   SMSGMM_NewMember
--   SMSGMM_TierUpgrade
--   SMSGMM_BonusAward

-- If rows are missing, insert them (Normal level):
INSERT INTO Configuration.Services_Logging (ServiceID, SubsystemID, LogLevel, ModifiedDate)
VALUES
    ('SmsGatewayMM', 'SMSGMM_NewMember',    0, GETDATE()),
    ('SmsGatewayMM', 'SMSGMM_TierUpgrade',  0, GETDATE()),
    ('SmsGatewayMM', 'SMSGMM_BonusAward',   0, GETDATE());

-- To set Debug during verification (reverts to Normal after testing):
UPDATE Configuration.Services_Logging
SET LogLevel = 1, ModifiedDate = GETDATE()
WHERE ServiceID = 'SmsGatewayMM';

-- Revert to Normal after testing:
UPDATE Configuration.Services_Logging
SET LogLevel = 0, ModifiedDate = GETDATE()
WHERE ServiceID = 'SmsGatewayMM';
```

- [ ] Log level rows exist for all three subsystems
- [ ] Log level set to 1 (Debug) for verification window

---

## Step 1 — Run new stored procedures (DB)

Target: `PE_Barrel_Cloud_Master` (prod) or `PE_Barrel_UAT_260521` (UAT).

Run each file in `docs/sql/NEW_SPs/` in the order listed. All use `CREATE OR ALTER` and are safe to re-run if needed.

**V2 Get SPs (claim-only — V1 originals untouched):**
- [ ] `PE_GET_NEXT_NEW_MEMBER_MM_V2.sql`
- [ ] `PE_GET_NEXT_TIER_UPGRADE_MM_V2.sql`
- [ ] `PE_GET_NEXT_BONUS_AWARD_MM_V2.sql`

**Confirm SPs (sets SubmittedToHostSMS=1 after HTTP 202):**
- [ ] `PE_CONFIRM_SENT_NEW_MEMBER_MM.sql`
- [ ] `PE_CONFIRM_SENT_TIER_UPGRADE_MM.sql`
- [ ] `PE_CONFIRM_SENT_BONUS_AWARD_MM.sql`

**Reset SPs (clears InTransmission on failure for re-queue):**
- [ ] `PE_RESET_FAILED_NEW_MEMBER_MM.sql`
- [ ] `PE_RESET_FAILED_TIER_UPGRADE_MM.sql`
- [ ] `PE_RESET_FAILED_BONUS_AWARD_MM.sql`

**Reaper SPs (auto-resets orphaned in-flight records older than N minutes):**
- [ ] `PE_REAP_STUCK_NEW_MEMBER_MM.sql`
- [ ] `PE_REAP_STUCK_TIER_UPGRADE_MM.sql`
- [ ] `PE_REAP_STUCK_BONUS_AWARD_MM.sql`

Verify each SP exists after running:
```sql
SELECT name FROM sys.objects
WHERE schema_id = SCHEMA_ID('SMSGateway')
  AND type = 'P'
  AND name LIKE '%_MM%'
ORDER BY name;
```
- [ ] 12 new SPs confirmed present (plus the existing V1 SPs and check SPs)

---

## Step 2 — Stop service

On the deployment server:

```powershell
Stop-Service -Name "SMS Gateway MessageMedia"
# Verify stopped:
Get-Service -Name "SMS Gateway MessageMedia" | Select-Object Status
```

- [ ] Service status is Stopped

---

## Step 3 — Deploy new binary

Publish from Visual Studio 2022:
- Project: `SmsGatewayMM`
- Profile: publish to the deployment folder (overwrite existing files)

Or via CLI:
```powershell
dotnet publish SmsGatewayMM\SmsGatewayMM.csproj -c Release -o "C:\peservices\sms-gateway-mm\"
```

- [ ] Binary deployed

---

## Step 4 — Verify config (no new keys required)

Check `C:\peservices\configs\appsettings-SMSGMM.json`:
- No new keys are required. The two new keys (`ReaperCutoffMinutes`, `ReaperIntervalPolls`) default correctly from `appsettings.json` (10 and 6 respectively).
- Confirm the existing `BaseUrl`, `AuthToken`, and `ConnectionStrings:Barrel` are present.

```json
{
  "SmsMm": {
    "BaseUrl": "https://api.messagemedia.com",
    "AuthToken": "<current-token>",
    "ReaperCutoffMinutes": 10,
    "ReaperIntervalPolls": 6
  },
  "ConnectionStrings": {
    "Barrel": "<connection-string>"
  }
}
```

- [ ] Config file present at `C:\peservices\configs\appsettings-SMSGMM.json`
- [ ] `BaseUrl`, `AuthToken`, and `Barrel` connection string are set

---

## Step 5 — Start service

```powershell
Start-Service -Name "SMS Gateway MessageMedia"
Get-Service -Name "SMS Gateway MessageMedia" | Select-Object Status
```

- [ ] Service status is Running

---

## Step 6 — Verify from log

Log location: `C:\Logs\SMSGMM\SMSGMM_Log_<MM-DD-YYYY>.txt`

**Startup (Normal level):**
```
=== SmsGatewayMM started ===
NewMember worker started
TierUpgrade worker started
BonusAward worker started
```
- [ ] All three workers logged as started

**On a successful send (Normal level):**
```
BonusAward: confirmed id=<N> venue=<N> message_id=<uuid>
```
- [ ] `confirmed` line appears with a `message_id` UUID

**On a failed send (Error level, e.g. simulate with bad auth):**
```
BonusAward: rejected id=<N> venue=<N> -- HTTP 401 body=... -- reset for retry
```
Then after the next poll cycle, the record should be back to `InTransmission=0` in the DB.

**Reaper (Debug level, after ~60s):**
```
NewMember: reaper ran (cutoff=10m)
TierUpgrade: reaper ran (cutoff=10m)
BonusAward: reaper ran (cutoff=10m)
```
- [ ] Reaper log visible (requires Debug log level — see Step 0)

**DB verification after a successful send:**
```sql
SELECT TOP 10
    NewMember_HostSMSID,
    InTransmission,
    SubmittedToHostSMS,
    SubmittedToHostSMSDateTime
FROM SMSGateway.NewMember_Host_SMS
ORDER BY NewMember_HostSMSID DESC;
-- Confirmed records: SubmittedToHostSMS=1
```
- [ ] Recently processed record shows `SubmittedToHostSMS=1`

---

## Step 7 — Set log level back to Normal

After verification window:
```sql
UPDATE Configuration.Services_Logging
SET LogLevel = 0, ModifiedDate = GETDATE()
WHERE ServiceID = 'SmsGatewayMM';
```
- [ ] Log level returned to 0 (Normal) — no service restart required

---

## Rollback

If any issue is found after deployment:

1. Stop the service
2. Redeploy the previous binary
3. Start the service

No SP changes are needed. The V1 Get SPs (`PE_GET_NEXT_NEW_MEMBER_MM`, `PE_GET_NEXT_TIER_UPGRADE_MM`, `PE_GET_NEXT_BONUS_AWARD_MM`) are completely untouched and the old binary will use them automatically.

---

## Open Follow-ups (not deployment blockers)

- Verify `Message_Body_Audit_Log` PK column: `EXEC sp_help 'SMSGateway.Message_Body_Audit_Log'` on the target DB, then add `message_id` storage to the Confirm SPs (deferred from LMDTS-64).
- Rotate the compromised MessageMedia token (`UgCJZEjREUJgQGuXOsyf` hardcoded in legacy repo).
