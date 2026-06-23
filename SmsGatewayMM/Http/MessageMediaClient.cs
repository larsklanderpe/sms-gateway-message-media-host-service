namespace SmsGatewayMM.Http;

using System.Net.Http;
using System.Text;
using System.Text.Json;
using SmsGatewayMM.Models;

class MessageMediaClient
{
    private readonly IHttpClientFactory _factory;

    public MessageMediaClient(IHttpClientFactory factory) => _factory = factory;

    public async Task<SendResult> SendAsync(SmsReadyMessage message, CancellationToken ct)
    {
        var client = _factory.CreateClient("MessageMedia");

        // source_number is an alphanumeric sender ID (brand tag), not a phone number.
        // MessageMedia rejects it unless source_number_type is declared explicitly -- it
        // cannot be inferred from an alpha value. Mirrors the proven-good production request.
        var payload = new
        {
            messages = new[]
            {
                new
                {
                    content = message.Content,
                    destination_number = message.DestinationNumber,
                    format = "SMS",
                    source_number = message.SourceNumber,
                    source_number_type = "ALPHANUMERIC"
                }
            }
        };

        var content = new StringContent(
            JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        var response = await client.PostAsync("v1/messages", content, ct);
        var body = await response.Content.ReadAsStringAsync(ct);
        return new SendResult(response.IsSuccessStatusCode, (int)response.StatusCode, body);
    }
}

record SendResult(bool Success, int StatusCode, string? Body);
