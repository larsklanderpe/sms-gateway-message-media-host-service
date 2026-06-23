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
    // Use only scheme + host from config; MessageMediaClient appends the "v1/messages"
    // path. This tolerates a config value that mistakenly includes the path, which would
    // otherwise resolve to /v1/v1/messages and fail every send.
    client.BaseAddress = new Uri(new Uri(config.MessageMediaBaseUrl).GetLeftPart(UriPartial.Authority));
    var credentials = Convert.ToBase64String(
        Encoding.ASCII.GetBytes($"{config.MessageMediaApiKey}:{config.MessageMediaApiSecret}"));
    client.DefaultRequestHeaders.Authorization =
        new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", credentials);
});

builder.Services.AddSingleton<MessageMediaClient>();

var host = builder.Build();

var data = host.Services.GetRequiredService<SmsDataAccess>();
var mmClient = host.Services.GetRequiredService<MessageMediaClient>();
var log = host.Services.GetRequiredService<FileLogger>();

// Three independent workers -- one per feed, no waterfall priority
var workerHost = new HostBuilder()
    .ConfigureServices(services =>
    {
        services.AddSingleton(config);
        services.AddSingleton(log);
        services.AddSingleton(data);
        services.AddSingleton(mmClient);
        // AddHostedService<T> registers via TryAddEnumerable, which dedupes by implementation
        // type -- three SmsWorker registrations would collapse to one (only NewMember runs).
        // Register as IHostedService directly so all three feed workers start.
        services.AddSingleton<IHostedService>(sp => new SmsWorker(new NewMemberStrategy(config), data, mmClient, log, config));
        services.AddSingleton<IHostedService>(sp => new SmsWorker(new TierUpgradeStrategy(config), data, mmClient, log, config));
        services.AddSingleton<IHostedService>(sp => new SmsWorker(new BonusAwardStrategy(config), data, mmClient, log, config));
    })
    .UseWindowsService()
    .Build();

var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "unknown";
log.LogStartup($"=== SMS Gateway MessageMedia started === Version={version} | Runtime={System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription}");

await workerHost.RunAsync();
