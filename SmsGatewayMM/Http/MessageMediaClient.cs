namespace SmsGatewayMM.Http;

using System.Net.Http;
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
