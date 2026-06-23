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
                    $"{_strategy.FeedName}: unhandled exception -- {ex.Message}");
            }

            await Task.Delay(TimeSpan.FromSeconds(_config.PollIntervalSeconds), ct);
        }
    }
}
