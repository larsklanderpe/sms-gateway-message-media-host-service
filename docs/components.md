# Components

## Data flow

```
PEBarrel DB (SMSGateway schema)
    |
    |-- NewMember_Host_SMS
    |-- TierUpgrades_Host_SMS
    |-- PlayerOffers_SMS
    |-- Message_Body_Model      (message templates + token defs)
    |-- ThirdPartySMSIDS        (host/venue config, ispehost flag)
    |-- Message_Body_Audit_Log  (written by Get SPs on each send)
    |
    v
SmsDataAccess (Dapper, SP-only)
    |
    |-- HasPending(strategy)  -->  PE_CHECK_*_QUEUE_MM  (returns 1 row or empty)
    |-- GetNext(strategy)     -->  PE_GET_NEXT_*_MM     (marks InTransmission, returns message)
    |
    v
SmsWorker x3 (BackgroundService, 10-second poll)
    |
    NewMemberStrategy   --> PE_CHECK_NEW_MEMBER_QUEUE_MM / PE_GET_NEXT_NEW_MEMBER_MM
    TierUpgradeStrategy --> PE_CHECK_TIER_UPGRADE_QUEUE_MM / PE_GET_NEXT_TIER_UPGRADE_MM
    BonusAwardStrategy  --> PE_CHECK_BONUS_AWARD_QUEUE_MM / PE_GET_NEXT_BONUS_AWARD_MM
    |
    v
MessageMediaClient (named IHttpClientFactory)
    |
    POST /v1/messages
    |
    v
MessageMedia REST API  -->  SMS delivered to member mobile
```

## Files

| File | Responsibility |
|---|---|
| `Program.cs` | Host setup, DI wiring, external config, startup log |
| `Config/SmsMmConfig.cs` | Typed config record bound from `SmsMm` config section |
| `Logging/FileLogger.cs` | Gen 3 PE FileLogger -- DB-driven log levels, daily rolling file |
| `Data/SmsDataAccess.cs` | All DB access via Dapper SP calls |
| `Http/MessageMediaClient.cs` | MessageMedia REST API wrapper |
| `Models/SmsReadyMessage.cs` | Immutable record returned by Get SPs |
| `Workers/ISmsWorkerStrategy.cs` | Feed identity interface |
| `Workers/SmsWorker.cs` | Generic BackgroundService poll loop |
| `Workers/NewMemberStrategy.cs` | NewMember feed SP names + subsystem name |
| `Workers/TierUpgradeStrategy.cs` | TierUpgrade feed SP names + subsystem name |
| `Workers/BonusAwardStrategy.cs` | BonusAward feed SP names + subsystem name |

## Stored procedures

| SP | Called by | Purpose |
|---|---|---|
| `SMSGateway.PE_CHECK_NEW_MEMBER_QUEUE_MM` | SmsDataAccess.HasPending | Age-suppress stale records, return 1 if pending |
| `SMSGateway.PE_GET_NEXT_NEW_MEMBER_MM` | SmsDataAccess.GetNext | Mark InTransmission, audit log, return message |
| `SMSGateway.PE_CHECK_TIER_UPGRADE_QUEUE_MM` | SmsDataAccess.HasPending | Age-suppress stale records, return 1 if pending |
| `SMSGateway.PE_GET_NEXT_TIER_UPGRADE_MM` | SmsDataAccess.GetNext | Mark InTransmission, audit log, return message |
| `SMSGateway.PE_CHECK_BONUS_AWARD_QUEUE_MM` | SmsDataAccess.HasPending | Orphan trap, queue depth alert, age-suppress, return 1 if pending |
| `SMSGateway.PE_GET_NEXT_BONUS_AWARD_MM` | SmsDataAccess.GetNext | Mark InTransmission, audit log, return message |

## Callers

Nothing calls this service -- it is a polling Windows Service. It is called by no upstream system.

## External dependencies

| Dependency | Purpose | Failure mode |
|---|---|---|
| PEBarrel DB (`Configuration.Services_Logging`) | Log level reads on every poll | Silently defaults to Normal (0) |
| PEBarrel DB (`SMSGateway.*`) | Queue data, audit log | Workers log error and continue polling |
| MessageMedia REST API | SMS delivery | Logged as rejected send; record stays InTransmission (may need manual reset) |
