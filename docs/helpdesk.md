# SMS Gateway MessageMedia -- Help Desk Reference

## Service identity

| Item | Value |
|---|---|
| Windows service name | `SMS Gateway MessageMedia` |
| Service abbreviation | SMSGMM |
| Executable | `SmsGatewayMM.exe` |
| Install path | TBD at deployment |

## Log files

**Path:** `C:\Logs\SMSGMM\SMSGMM_Log_MM-DD-YYYY.txt`

One file per day, rolling daily. Retained for 30 days.

## Config file

**Path:** `C:\peservices\configs\appsettings-SMSGMM.json`

Contains connection strings and MessageMedia API credentials. Never committed to GitHub.

---

## IMPORTANT: Log levels are DB-driven, not file-driven

> **This service is a Windows Service.** Log level is stored in the database and read at runtime on every poll cycle. Changing the log level does **not** require a service restart.

Check current log level:

```sql
SELECT * FROM Configuration.Services_Logging
WHERE ServiceName = 'SmsGatewayMM'
```

Expected rows (one per subsystem):

| ServiceName | SubsystemName | LogLevel | LogEnabled |
|---|---|---|---|
| SmsGatewayMM | SMSGMM_NewMember | 0 | 1 |
| SmsGatewayMM | SMSGMM_TierUpgrade | 0 | 1 |
| SmsGatewayMM | SMSGMM_BonusAward | 0 | 1 |

**If any row is missing the subsystem silently defaults to Normal (0). Verify all three rows exist before handing over to help desk.**

Insert rows on first deployment (run once per barrel DB):

```sql
INSERT INTO Configuration.Services_Logging (ServiceName, SubsystemName, LogLevel, LogEnabled)
VALUES
    ('SmsGatewayMM', 'SMSGMM_NewMember',   0, 1),
    ('SmsGatewayMM', 'SMSGMM_TierUpgrade', 0, 1),
    ('SmsGatewayMM', 'SMSGMM_BonusAward',  0, 1)
```

Log levels: `0 = Normal`, `1 = Debug`, `2 = Verbose`

Change log level for a subsystem (no restart needed):

```sql
UPDATE Configuration.Services_Logging
SET LogLevel = 1  -- 1=Debug, 2=Verbose
WHERE ServiceName = 'SmsGatewayMM' AND SubsystemName = 'SMSGMM_BonusAward'
```

---

## Restart procedure

1. Open Services (`services.msc`) or use `sc`:
   ```
   sc stop "SMS Gateway MessageMedia"
   sc start "SMS Gateway MessageMedia"
   ```
2. Check log file for startup line: `=== SMS Gateway MessageMedia started === Version=...`
3. Verify three worker started lines appear (NewMember, TierUpgrade, BonusAward)

## Liveness check

No HTTP endpoint. Confirm the service is alive by:
1. Checking the Windows service status (`sc query "SMS Gateway MessageMedia"`)
2. Verifying the log file has been written within the last 30 seconds (the poll interval is 10 seconds)

---

## Common failure modes

### Service stops immediately after start

Check the log file for the startup line. If absent, the external config file is likely missing or has an invalid connection string.

Verify: `C:\peservices\configs\appsettings-SMSGMM.json` exists and `BarrelConnectionString` is valid.

### No SMS being sent but service is running

1. Check the barrel DB is reachable from the server.
2. Check `SMSGateway.NewMember_Host_SMS`, `TierUpgrades_Host_SMS`, `PlayerOffers_SMS` for records with `SubmittedToHostSMS = 0` and `InTransmission = 0` -- if none exist, the queues are genuinely empty.
3. If records exist but nothing moves, set log level to Debug and check for error lines.
4. Check MessageMedia API credentials in `appsettings-SMSGMM.json` -- a 401 from MessageMedia will appear in the log as a rejected send.

### Queue stalled -- records stuck as InTransmission = 1 but not sent

This can happen if the service crashed mid-send. Records marked `InTransmission = 1` with `SubmittedToHostSMSDateTime` set but no corresponding MessageMedia delivery are orphaned.

Resolution: manually reset the affected records after confirming no duplicate will be sent:

```sql
-- NewMember
UPDATE [SMSGateway].[NewMember_Host_SMS]
SET InTransmission = 0, SubmittedToHostSMS = 0, SubmittedToHostSMSDateTime = NULL
WHERE InTransmission = 1 AND SubmittedToHostSMSDateTime < DATEADD(MINUTE, -5, GETDATE())

-- TierUpgrade
UPDATE [SMSGateway].[TierUpgrades_Host_SMS]
SET InTransmission = 0, SubmittedToHostSMS = 0, SubmittedToHostSMSDateTime = NULL
WHERE InTransmission = 1 AND SubmittedToHostSMSDateTime < DATEADD(MINUTE, -5, GETDATE())

-- BonusAward
UPDATE [SMSGateway].[PlayerOffers_SMS]
SET InTransmission = 0, SubmittedToHostSMS = 0, SubmittedToHostSMSDateTime = NULL
WHERE InTransmission = 1 AND SubmittedToHostSMSDateTime < DATEADD(MINUTE, -5, GETDATE())
```

### Email alerts from the service

Two alert types are sent by `PE_CHECK_BONUS_AWARD_QUEUE_MM`:

- **Orphaned Records Suppressed** -- records with missing host or promotion references. Check `ThirdPartySMSIDS` and `Message_Body_Model` for missing entries.
- **Queue Depth Exceeds Threshold** -- more than 100 bonus award records pending today. May indicate the service is stalled or a large batch was loaded. Check service status first.
