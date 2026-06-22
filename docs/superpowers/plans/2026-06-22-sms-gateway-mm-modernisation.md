# SMS Gateway MessageMedia — .NET 10 Three-Feed Modernisation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `SMSGatewayMessageMediaHostService` as a .NET 10 Windows Service with three independent BackgroundService workers — one per SMS feed — eliminating the waterfall starvation problem in the original single-threaded pump.

**Architecture:** Three `SmsWorker` instances (BackgroundService, one registered per strategy) each own one feed via an `ISmsWorkerStrategy` interface, poll independently every 10 seconds, and call their own per-feed check/get stored procedures. A shared `MessageMediaClient` (named `IHttpClientFactory` client) handles HTTP without socket exhaustion. Gen 3 FileLogger reads log level from `Configuration.Services_Logging` in PEBarrel on every poll cycle.

**Tech Stack:** .NET 10, `Microsoft.Extensions.Hosting.WindowsServices`, Dapper (SP-only, no raw SQL), `IHttpClientFactory`, `System.Text.Json`, PE Gen 3 FileLogger pattern.

**Jira:** LMDTS-63 — https://playerelite.atlassian.net/browse/LMDTS-63

---

## Pre-Conditions Before Writing Code

- [ ] Obtain `SMSGateway.GET_UNTRANSMITTED_NEW_MEMBER_MM` from both PEAUS and PENEXUS
- [ ] Obtain `SMSGateway.GET_UNTRANSMITTED_TIER_UPGRADE_MM` from both PEAUS and PENEXUS
- [ ] Confirm output column names from both sub-SPs (must match DTOs exactly)
- [ ] Get fresh MessageMedia API credentials from portal — old hardcoded token is COMPROMISED
- [ ] Confirm `Configuration.Services_Logging` subsystem name for each worker (suggest: `SMSGMM_NewMember`, `SMSGMM_TierUpgrade`, `SMSGMM_BonusAward`)

---

## File Map

```
sms-gateway-message-media-host-service/
├── SmsGatewayMM/
│   ├── SmsGatewayMM.csproj
│   ├── Program.cs                          create
│   ├── appsettings.json                    create  (placeholder values only)
│   ├── AutoBuildNumber.targets             create  (copy from SSIVC)
│   ├── BuildNumber.txt                     gitignored
│   │
│   ├── Config/
│   │   └── SmsMmConfig.cs                  create  (typed config record)
│   │
│   ├── Logging/
│   │   └── FileLogger.cs                   create  (Gen 3 pattern from recurrent_processes_service_wins)
│   │
│   ├── Data/
│   │   └── SmsDataAccess.cs               create  (Dapper, SP calls only)
│   │
│   ├── Http/
│   │   └── MessageMediaClient.cs          create  (named IHttpClientFactory wrapper)
│   │
│   ├── Workers/
│   │   ├── ISmsWorkerStrategy.cs          create  (interface: FeedName, CheckProcedure, GetProcedure, SubsystemName)
│   │   ├── SmsWorker.cs                   create  (BackgroundService, one registration per strategy)
│   │   ├── NewMemberStrategy.cs           create
│   │   ├── TierUpgradeStrategy.cs         create
│   │   └── BonusAwardStrategy.cs          create
│   │
│   └── Models/
│       └── SmsReadyMessage.cs             create  (record: Id, VenueId, SourceNumber, DestinationNumber, Content)
│
├── docs/
│   ├── session-notes.md                   create
│   ├── helpdesk.md                        create
│   ├── design-decisions.md                create
│   ├── components.md                      create
│   ├── sql/
│   │   ├── PE_CHECK_FOR_AWARDS_IN_QUEUE_PEAUS.sql       captured
│   │   ├── PE_CHECK_FOR_AWARDS_IN_QUEUE_MM_PEAUS.sql    captured
│   │   ├── PE_GET_UNTRANSMITTED_BONUS_AWARD_MM_PEAUS.sql captured
│   │   ├── PE_CHECK_FOR_AWARDS_IN_QUEUE_MM_PENEXUS.sql  captured
│   │   ├── PE_GET_UNTRANSMITTED_BONUS_AWARD_MM_PENEXUS.sql captured
│   │   ├── GET_UNTRANSMITTED_NEW_MEMBER_MM_PEAUS.sql    NEEDED
│   │   ├── GET_UNTRANSMITTED_NEW_MEMBER_MM_PENEXUS.sql  NEEDED
│   │   ├── GET_UNTRANSMITTED_TIER_UPGRADE_MM_PEAUS.sql  NEEDED
│   │   ├── GET_UNTRANSMITTED_TIER_UPGRADE_MM_PENEXUS.sql NEEDED
│   │   └── NEW_SPs/
│   │       ├── PE_CHECK_NEW_MEMBER_QUEUE_MM.sql         create (per-feed, no waterfall)
│   │       ├── PE_GET_NEXT_NEW_MEMBER_MM.sql            create
│   │       ├── PE_CHECK_TIER_UPGRADE_QUEUE_MM.sql       create
│   │       ├── PE_GET_NEXT_TIER_UPGRADE_MM.sql          create
│   │       ├── PE_CHECK_BONUS_AWARD_QUEUE_MM.sql        create
│   │       └── PE_GET_NEXT_BONUS_AWARD_MM.sql           create
│   └── superpowers/
│       ├── plans/
│       │   └── 2026-06-22-sms-gateway-mm-modernisation.md  (this file)
│       └── deliverables/
│           └── .gitkeep
```

---

## SP Design — New Per-Feed Architecture

The six existing SPs (three check variants + `PE_GET_UNTRANSMITTED_BONUS_AWARD_MM` + two sub-SPs)
are **retired**. Six independent per-feed pairs replace them. Each pair is identical in contract:

- **Check SP** — lightweight, no data mutations. Returns 1 row if a pending record exists, 0 rows if empty.
- **Get SP** — marks `InTransmission = 1`, logs to `Message_Body_Audit_Log`, returns the ready-to-send message.

Standard output columns from all six Get SPs:
```sql
id             INT           -- feed-specific PK
venue_id       INT
source_number  VARCHAR(11)   -- TextMessageSource (sender ID / header)
dest_number    VARCHAR(25)   -- HostMobile formatted to +61
content        VARCHAR(1024) -- body with tokens merged server-side
```

Safeguards carried from PEAUS to ALL six new SPs:
- Age suppression: records > 1 hour old suppressed before check
- PE Host Guard: if `ispehost = 1`, suppress if already transmitted to that host today
- Orphaned record trap (BonusAward Get only): email + suppress if ThirdPartySMSIDS or Message_Body_Model refs missing
- Queue depth alert (BonusAward Check only): email if today's unsent count > 100

---

## Task 1: Repo Scaffold

**Files:**
- Create: `SmsGatewayMM/SmsGatewayMM.csproj`
- Create: `SmsGatewayMM/AutoBuildNumber.targets`
- Create: `.gitignore`
- Create: `SmsGatewayMM.sln`

- [ ] Create `.gitignore`:

```
bin/
obj/
*.user
.vs/
BuildNumber.txt
appsettings-*.json
```

- [ ] Scaffold solution and worker project:

```
dotnet new sln -n SmsGatewayMM
dotnet new worker -n SmsGatewayMM -o SmsGatewayMM --framework net10.0
dotnet sln add SmsGatewayMM/SmsGatewayMM.csproj
```

- [ ] Replace generated `.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk.Worker">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <WindowsService>true</WindowsService>
    <AutoBuildMajor>1</AutoBuildMajor>
    <AutoBuildMinor>0</AutoBuildMinor>
    <ProjectStartDate>2026-06-22</ProjectStartDate>
  </PropertyGroup>
  <Import Project="AutoBuildNumber.targets" />
  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Hosting.WindowsServices" Version="10.*" />
    <PackageReference Include="Dapper" Version="2.*" />
    <PackageReference Include="Microsoft.Data.SqlClient" Version="6.*" />
  </ItemGroup>
</Project>
```

- [ ] Copy `AutoBuildNumber.targets` from `D:\vc-newpe-repos\self-serve-in-venue-service\SSIVC\AutoBuildNumber.targets` — do not modify.

- [ ] Create `SmsGatewayMM/BuildNumber.txt` with content `0` and verify `.gitignore` excludes it.

- [ ] Run `dotnet build` — expect clean compile with version 1.0.1.0.

- [ ] Commit:

```bash
git add .gitignore SmsGatewayMM.sln SmsGatewayMM/
git commit -m "feat(LMDTS-63): scaffold .NET 10 worker project with auto build versioning"
```

---

## Task 2: Config and appsettings

**Files:**
- Create: `SmsGatewayMM/appsettings.json`
- Create: `SmsGatewayMM/Config/SmsMmConfig.cs`
- Create (external, never committed): `C:\peservices\configs\appsettings-SMSGMM.json`

- [ ] Create `SmsGatewayMM/appsettings.json` (placeholder values — no credentials):

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    }
  },
  "SmsMm": {
    "PollIntervalSeconds": 10,
    "BarrelConnectionString": "PLACEHOLDER",
    "MessageMediaApiKey": "PLACEHOLDER",
    "MessageMediaApiSecret": "PLACEHOLDER",
    "MessageMediaBaseUrl": "https://api.messagemedia.com",
    "LogRoot": "C:\\Logs\\SMSGMM",
    "LogSubsystemNewMember": "SMSGMM_NewMember",
    "LogSubsystemTierUpgrade": "SMSGMM_TierUpgrade",
    "LogSubsystemBonusAward": "SMSGMM_BonusAward"
  }
}
```

- [ ] Create `SmsGatewayMM/Config/SmsMmConfig.cs`:

```csharp
namespace SmsGatewayMM.Config;

record SmsMmConfig
{
    public int PollIntervalSeconds { get; init; } = 10;
    public string BarrelConnectionString { get; init; } = "";
    public string MessageMediaApiKey { get; init; } = "";
    public string MessageMediaApiSecret { get; init; } = "";
    public string MessageMediaBaseUrl { get; init; } = "https://api.messagemedia.com";
    public string LogRoot { get; init; } = @"C:\Logs\SMSGMM";
    public string LogSubsystemNewMember { get; init; } = "SMSGMM_NewMember";
    public string LogSubsystemTierUpgrade { get; init; } = "SMSGMM_TierUpgrade";
    public string LogSubsystemBonusAward { get; init; } = "SMSGMM_BonusAward";
}
```

- [ ] Create `C:\peservices\configs\appsettings-SMSGMM.json` on the target machine with real credentials (never committed):

```json
{
  "SmsMm": {
    "BarrelConnectionString": "Server=...;Database=PE_Barrel_...;...",
    "MessageMediaApiKey": "YOUR_FRESH_KEY_HERE",
    "MessageMediaApiSecret": "YOUR_FRESH_SECRET_HERE"
  }
}
```

- [ ] Commit:

```bash
git add SmsGatewayMM/appsettings.json SmsGatewayMM/Config/
git commit -m "feat(LMDTS-63): add typed config and placeholder appsettings"
```

---

## Task 3: Gen 3 FileLogger

**Files:**
- Create: `SmsGatewayMM/Logging/FileLogger.cs`

Reference: `D:\vc-newpe-repos\recurrent_processes_service_wins\RecurrentProcessesService\FileLogger.cs`

- [ ] Create `SmsGatewayMM/Logging/FileLogger.cs`:

```csharp
namespace SmsGatewayMM.Logging;

using Dapper;
using Microsoft.Data.SqlClient;

class FileLogger
{
    private readonly string _connectionString;
    private readonly string _logRoot;
    private readonly string _serviceName;

    public FileLogger(string connectionString, string logRoot, string serviceName)
    {
        _connectionString = connectionString;
        _logRoot = logRoot;
        _serviceName = serviceName;
        Directory.CreateDirectory(logRoot);
    }

    public void LogStartup(string message) => Write("STARTUP", message, null);
    public void LogError(string subsystem, string message) => Write("ERROR", message, subsystem);

    public void LogNormal(string subsystem, string message)
    {
        if (GetSubsystemLogLevel(subsystem) >= 0) Write("INFO", message, subsystem);
    }

    public void LogDebug(string subsystem, string message)
    {
        if (GetSubsystemLogLevel(subsystem) >= 1) Write("DEBUG", message, subsystem);
    }

    public void LogVerbose(string subsystem, string message)
    {
        if (GetSubsystemLogLevel(subsystem) >= 2) Write("VERBOSE", message, subsystem);
    }

    private int GetSubsystemLogLevel(string subsystemName)
    {
        try
        {
            using var conn = new SqlConnection(_connectionString);
            return conn.QueryFirstOrDefault<int?>(
                "SELECT LogLevel FROM Configuration.Services_Logging " +
                "WHERE ServiceName = @SN AND SubsystemName = @Sub AND LogEnabled = 1",
                new { SN = _serviceName, Sub = subsystemName }) ?? 0;
        }
        catch { return 0; }
    }

    private void Write(string level, string message, string? subsystem)
    {
        var ts = DateTime.Now;
        var line = $"{ts:yyyy-MM-dd HH:mm:ss.fff} [{level}]" +
                   (subsystem != null ? $" [{subsystem}]" : "") +
                   $" {message}";
        var path = Path.Combine(_logRoot, $"SMSGMM_Log_{ts:MM-dd-yyyy}.txt");
        try { File.AppendAllText(path, line + Environment.NewLine); } catch { }
        Console.WriteLine(line);
    }
}
```

- [ ] Run `dotnet build` — clean compile.

- [ ] Commit:

```bash
git add SmsGatewayMM/Logging/
git commit -m "feat(LMDTS-63): add Gen 3 FileLogger with DB-driven log levels"
```

---

## Task 4: SmsReadyMessage + ISmsWorkerStrategy

**Files:**
- Create: `SmsGatewayMM/Models/SmsReadyMessage.cs`
- Create: `SmsGatewayMM/Workers/ISmsWorkerStrategy.cs`

- [ ] Create `SmsGatewayMM/Models/SmsReadyMessage.cs`:

```csharp
namespace SmsGatewayMM.Models;

record SmsReadyMessage(
    int Id,
    int VenueId,
    string SourceNumber,
    string DestinationNumber,
    string Content
);
```

- [ ] Create `SmsGatewayMM/Workers/ISmsWorkerStrategy.cs`:

```csharp
namespace SmsGatewayMM.Workers;

interface ISmsWorkerStrategy
{
    string FeedName { get; }
    string SubsystemName { get; }
    string CheckProcedure { get; }
    string GetProcedure { get; }
}
```

- [ ] Run `dotnet build` — clean compile.

- [ ] Commit:

```bash
git add SmsGatewayMM/Models/ SmsGatewayMM/Workers/ISmsWorkerStrategy.cs
git commit -m "feat(LMDTS-63): add SmsReadyMessage and ISmsWorkerStrategy"
```

---

## Task 5: Three Strategy Implementations

**Files:**
- Create: `SmsGatewayMM/Workers/NewMemberStrategy.cs`
- Create: `SmsGatewayMM/Workers/TierUpgradeStrategy.cs`
- Create: `SmsGatewayMM/Workers/BonusAwardStrategy.cs`

SP names reference the NEW per-feed SPs (Task 10 below).

- [ ] Create `SmsGatewayMM/Workers/NewMemberStrategy.cs`:

```csharp
namespace SmsGatewayMM.Workers;

using SmsGatewayMM.Config;

class NewMemberStrategy : ISmsWorkerStrategy
{
    private readonly SmsMmConfig _config;
    public NewMemberStrategy(SmsMmConfig config) => _config = config;

    public string FeedName => "NewMember";
    public string SubsystemName => _config.LogSubsystemNewMember;
    public string CheckProcedure => "SMSGateway.PE_CHECK_NEW_MEMBER_QUEUE_MM";
    public string GetProcedure => "SMSGateway.PE_GET_NEXT_NEW_MEMBER_MM";
}
```

- [ ] Create `SmsGatewayMM/Workers/TierUpgradeStrategy.cs`:

```csharp
namespace SmsGatewayMM.Workers;

using SmsGatewayMM.Config;

class TierUpgradeStrategy : ISmsWorkerStrategy
{
    private readonly SmsMmConfig _config;
    public TierUpgradeStrategy(SmsMmConfig config) => _config = config;

    public string FeedName => "TierUpgrade";
    public string SubsystemName => _config.LogSubsystemTierUpgrade;
    public string CheckProcedure => "SMSGateway.PE_CHECK_TIER_UPGRADE_QUEUE_MM";
    public string GetProcedure => "SMSGateway.PE_GET_NEXT_TIER_UPGRADE_MM";
}
```

- [ ] Create `SmsGatewayMM/Workers/BonusAwardStrategy.cs`:

```csharp
namespace SmsGatewayMM.Workers;

using SmsGatewayMM.Config;

class BonusAwardStrategy : ISmsWorkerStrategy
{
    private readonly SmsMmConfig _config;
    public BonusAwardStrategy(SmsMmConfig config) => _config = config;

    public string FeedName => "BonusAward";
    public string SubsystemName => _config.LogSubsystemBonusAward;
    public string CheckProcedure => "SMSGateway.PE_CHECK_BONUS_AWARD_QUEUE_MM";
    public string GetProcedure => "SMSGateway.PE_GET_NEXT_BONUS_AWARD_MM";
}
```

- [ ] Run `dotnet build` — clean compile.

- [ ] Commit:

```bash
git add SmsGatewayMM/Workers/New*Strategy.cs SmsGatewayMM/Workers/TierUpgradeStrategy.cs SmsGatewayMM/Workers/BonusAwardStrategy.cs
git commit -m "feat(LMDTS-63): add three ISmsWorkerStrategy implementations"
```

---

## Task 6: SmsDataAccess

**Files:**
- Create: `SmsGatewayMM/Data/SmsDataAccess.cs`

**VERIFY BEFORE WRITING DTO MAPPING:** Run `EXEC sp_helptext 'SMSGateway.PE_GET_NEXT_NEW_MEMBER_MM'` etc. against the UAT barrel (`101.0.69.158`) to confirm output column names. The mapping below uses columns agreed in the SP design above — confirm they match the actual new SPs.

- [ ] Create `SmsGatewayMM/Data/SmsDataAccess.cs`:

```csharp
namespace SmsGatewayMM.Data;

using Dapper;
using Microsoft.Data.SqlClient;
using SmsGatewayMM.Models;
using SmsGatewayMM.Workers;
using System.Data;

class SmsDataAccess
{
    private readonly string _connectionString;

    public SmsDataAccess(string connectionString) => _connectionString = connectionString;

    public bool HasPending(ISmsWorkerStrategy strategy)
    {
        using var conn = new SqlConnection(_connectionString);
        var result = conn.QueryFirstOrDefault<int>(
            strategy.CheckProcedure,
            commandType: CommandType.StoredProcedure);
        return result > 0;
    }

    public SmsReadyMessage? GetNext(ISmsWorkerStrategy strategy)
    {
        using var conn = new SqlConnection(_connectionString);
        var row = conn.QueryFirstOrDefault<dynamic>(
            strategy.GetProcedure,
            commandType: CommandType.StoredProcedure);

        if (row == null) return null;

        return new SmsReadyMessage(
            Id: (int)row.id,
            VenueId: (int)row.venue_id,
            SourceNumber: (string)row.source_number,
            DestinationNumber: (string)row.dest_number,
            Content: (string)row.content
        );
    }
}
```

- [ ] Run `dotnet build` — clean compile.

- [ ] Commit:

```bash
git add SmsGatewayMM/Data/
git commit -m "feat(LMDTS-63): add SmsDataAccess with Dapper SP calls"
```

---

## Task 7: MessageMediaClient

**Files:**
- Create: `SmsGatewayMM/Http/MessageMediaClient.cs`

MessageMedia REST: `POST /v1/messages` with Basic auth, JSON body.

- [ ] Create `SmsGatewayMM/Http/MessageMediaClient.cs`:

```csharp
namespace SmsGatewayMM.Http;

using System.Text;
using System.Text.Json;
using SmsGatewayMM.Models;

class MessageMediaClient
{
    private readonly IHttpClientFactory _factory;

    public MessageMediaClient(IHttpClientFactory factory) => _factory = factory;

    public async Task<bool> SendAsync(SmsReadyMessage message, CancellationToken ct)
    {
        var client = _factory.CreateClient("MessageMedia");

        var payload = new
        {
            messages = new[]
            {
                new
                {
                    source_number = message.SourceNumber,
                    destination_number = message.DestinationNumber,
                    content = message.Content
                }
            }
        };

        var content = new StringContent(
            JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        var response = await client.PostAsync("v1/messages", content, ct);
        return response.IsSuccessStatusCode;
    }
}
```

- [ ] Run `dotnet build` — clean compile.

- [ ] Commit:

```bash
git add SmsGatewayMM/Http/
git commit -m "feat(LMDTS-63): add MessageMediaClient using named IHttpClientFactory"
```

---

## Task 8: SmsWorker

**Files:**
- Create: `SmsGatewayMM/Workers/SmsWorker.cs`

- [ ] Create `SmsGatewayMM/Workers/SmsWorker.cs`:

```csharp
namespace SmsGatewayMM.Workers;

using SmsGatewayMM.Config;
using SmsGatewayMM.Data;
using SmsGatewayMM.Http;
using SmsGatewayMM.Logging;

class SmsWorker : BackgroundService
{
    private readonly ISmsWorkerStrategy _strategy;
    private readonly SmsDataAccess _data;
    private readonly MessageMediaClient _client;
    private readonly FileLogger _log;
    private readonly SmsMmConfig _config;

    public SmsWorker(
        ISmsWorkerStrategy strategy,
        SmsDataAccess data,
        MessageMediaClient client,
        FileLogger log,
        SmsMmConfig config)
    {
        _strategy = strategy;
        _data = data;
        _client = client;
        _log = log;
        _config = config;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        _log.LogNormal(_strategy.SubsystemName, $"{_strategy.FeedName} worker started");

        while (!ct.IsCancellationRequested)
        {
            try
            {
                if (_data.HasPending(_strategy))
                {
                    _log.LogDebug(_strategy.SubsystemName, $"{_strategy.FeedName}: pending record found");
                    var message = _data.GetNext(_strategy);

                    if (message != null)
                    {
                        _log.LogDebug(_strategy.SubsystemName,
                            $"{_strategy.FeedName}: sending id={message.Id} venue={message.VenueId} to={message.DestinationNumber}");

                        var sent = await _client.SendAsync(message, ct);

                        if (sent)
                            _log.LogNormal(_strategy.SubsystemName,
                                $"{_strategy.FeedName}: sent id={message.Id} venue={message.VenueId}");
                        else
                            _log.LogError(_strategy.SubsystemName,
                                $"{_strategy.FeedName}: MessageMedia rejected id={message.Id} venue={message.VenueId}");
                    }
                }
                else
                {
                    _log.LogVerbose(_strategy.SubsystemName, $"{_strategy.FeedName}: queue empty");
                }
            }
            catch (Exception ex)
            {
                _log.LogError(_strategy.SubsystemName,
                    $"{_strategy.FeedName}: unhandled exception — {ex.Message}");
            }

            await Task.Delay(TimeSpan.FromSeconds(_config.PollIntervalSeconds), ct);
        }
    }
}
```

- [ ] Run `dotnet build` — clean compile.

- [ ] Commit:

```bash
git add SmsGatewayMM/Workers/SmsWorker.cs
git commit -m "feat(LMDTS-63): add generic SmsWorker BackgroundService"
```

---

## Task 9: Program.cs

**Files:**
- Modify: `SmsGatewayMM/Program.cs`

- [ ] Replace generated `Program.cs`:

```csharp
using System.Reflection;
using System.Text;
using SmsGatewayMM.Config;
using SmsGatewayMM.Data;
using SmsGatewayMM.Http;
using SmsGatewayMM.Logging;
using SmsGatewayMM.Workers;

var builder = Host.CreateApplicationBuilder(args);

var externalConfig = @"C:\peservices\configs\appsettings-SMSGMM.json";
if (File.Exists(externalConfig))
    builder.Configuration.AddJsonFile(externalConfig, optional: false, reloadOnChange: false);

builder.Services.AddWindowsService(opts => opts.ServiceName = "SMS Gateway MessageMedia");

var config = builder.Configuration.GetSection("SmsMm").Get<SmsMmConfig>()
    ?? throw new InvalidOperationException("SmsMm config section missing");

builder.Services.AddSingleton(config);
builder.Services.AddSingleton(new FileLogger(config.BarrelConnectionString, config.LogRoot, "SmsGatewayMM"));
builder.Services.AddSingleton(new SmsDataAccess(config.BarrelConnectionString));

builder.Services.AddHttpClient("MessageMedia", client =>
{
    client.BaseAddress = new Uri(config.MessageMediaBaseUrl);
    var credentials = Convert.ToBase64String(
        Encoding.ASCII.GetBytes($"{config.MessageMediaApiKey}:{config.MessageMediaApiSecret}"));
    client.DefaultRequestHeaders.Authorization =
        new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", credentials);
});

builder.Services.AddSingleton<MessageMediaClient>();

// Three independent workers — each gets its own strategy instance
var host = builder.Build();

var data = host.Services.GetRequiredService<SmsDataAccess>();
var client = host.Services.GetRequiredService<MessageMediaClient>();
var log = host.Services.GetRequiredService<FileLogger>();

// Startup log
var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "unknown";
log.LogStartup($"=== SMS Gateway MessageMedia started === Version={version} | Runtime={System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription}");

host.Run();
```

> **Note on worker registration:** The three `SmsWorker` instances need separate registrations with distinct strategy instances. The simplest approach for `AddHostedService` is to register them explicitly in `Program.cs` after the host is built, or use factory overloads. Adjust as needed if the DI wiring produces ordering issues at startup — the intent is three independently-running `BackgroundService` loops.

- [ ] Run `dotnet build` — clean compile.
- [ ] Run `dotnet run` — expect startup log line, three workers polling.

- [ ] Commit:

```bash
git add SmsGatewayMM/Program.cs
git commit -m "feat(LMDTS-63): wire three-feed host with external config and named HttpClient"
```

---

## Task 10: New Per-Feed Stored Procedures

**Files:**
- Create: `docs/sql/NEW_SPs/PE_CHECK_NEW_MEMBER_QUEUE_MM.sql`
- Create: `docs/sql/NEW_SPs/PE_GET_NEXT_NEW_MEMBER_MM.sql`
- Create: `docs/sql/NEW_SPs/PE_CHECK_TIER_UPGRADE_QUEUE_MM.sql`
- Create: `docs/sql/NEW_SPs/PE_GET_NEXT_TIER_UPGRADE_MM.sql`
- Create: `docs/sql/NEW_SPs/PE_CHECK_BONUS_AWARD_QUEUE_MM.sql`
- Create: `docs/sql/NEW_SPs/PE_GET_NEXT_BONUS_AWARD_MM.sql`

**GATE:** Capture `GET_UNTRANSMITTED_NEW_MEMBER_MM` and `GET_UNTRANSMITTED_TIER_UPGRADE_MM` from both clouds first. Their token substitution and column logic is the source of truth for the new Get SPs.

Design rules:
1. All use `CREATE OR ALTER` with SP header comment block.
2. Check SPs: age suppression first → exists check → return 1 or empty.
3. Get SPs: PEAUS safeguards (PE Host Guard, age suppression) → mark InTransmission → audit log → return 5-column message with standardized column names (`id, venue_id, source_number, dest_number, content`).
4. BonusAward Check: add orphaned record email trap + queue depth alert (PEAUS feature).
5. Both clouds get identical SP logic — PENEXUS differences are treated as bugs to fix, not features to preserve.

- [ ] Capture missing sub-SPs from Lars
- [ ] Write all six SPs
- [ ] Run each `CREATE OR ALTER` against UAT barrel (`101.0.69.158`) and verify with `sp_helptext`
- [ ] Commit:

```bash
git add docs/sql/NEW_SPs/
git commit -m "feat(LMDTS-63): add six per-feed independent check/get SPs"
```

---

## Task 11: Standard Docs

**Files:**
- Create: `docs/helpdesk.md`
- Create: `docs/design-decisions.md`
- Create: `docs/components.md`
- Update: `docs/session-notes.md`

- [ ] Create `docs/helpdesk.md` — include:
  - Log location: `C:\Logs\SMSGMM\SMSGMM_Log_MM-DD-YYYY.txt`
  - Config: `C:\peservices\configs\appsettings-SMSGMM.json`
  - Service name: `SMS Gateway MessageMedia`
  - **PROMINENT CALLOUT:** Log level is DB-driven, stored in `Configuration.Services_Logging` in PEBarrel. Not file-driven. No restart needed to change level.
    ```sql
    -- Check/update log level
    SELECT * FROM Configuration.Services_Logging WHERE ServiceName = 'SmsGatewayMM'
    -- Levels: 0 = Normal, 1 = Debug, 2 = Verbose
    UPDATE Configuration.Services_Logging SET LogLevel = 1 WHERE ServiceName = 'SmsGatewayMM'
    ```
  - Restart procedure, common failure modes (DB unreachable, MessageMedia 401, queue stalled)

- [ ] Create `docs/design-decisions.md` — entry for three-worker pattern (why: waterfall starvation — if NewMember queue never empties, TierUpgrade and BonusAward are permanently starved).

- [ ] Create `docs/components.md` — data flow: PEBarrel `SMSGateway.*` tables → check/get SPs → `SmsDataAccess` → `SmsWorker` (×3) → `MessageMediaClient` → MessageMedia REST API.

- [ ] Commit:

```bash
git add docs/helpdesk.md docs/design-decisions.md docs/components.md
git commit -m "docs(LMDTS-63): add helpdesk, design-decisions, components"
```

---

## Task 12: GitHub Repo + Push

- [ ] Create GitHub repo: `gh repo create playerelite/sms-gateway-message-media-host-service --private`
- [ ] Set remote and push: `git remote add origin <url> && git push -u origin feature/LMDTS-63-dotnet10-three-feed-modernisation`
- [ ] Raise PR targeting `main` (not `master` — PE standard)

---

## Backlog Items

**Salesforce Journey Swap (per-venue routing)**
When a venue's `VenueID` maps to a Salesforce Marketing Cloud journey, route via SFMC journey trigger instead of direct MessageMedia POST. The `ISmsWorkerStrategy` / `MessageMediaClient` separation already isolates the delivery path — add an `ISmsDeliveryProvider` interface with `MessageMediaProvider` and `SalesforceProvider` implementations, resolved per-venue from a routing table. No worker logic changes needed.

**PENEXUS Bug — NewMember SELECT**
`PE_CHECK_FOR_AWARDS_IN_QUEUE_MM` on PENEXUS has `ISNULL(SuppressedFromTransmission, 0) = 1` in the NewMember final SELECT WHERE — always returns zero rows, so NewMember SMS is silently non-functional on NEXUS. Needs a hotfix on the NEXUS barrel DB before this new service goes live there.
