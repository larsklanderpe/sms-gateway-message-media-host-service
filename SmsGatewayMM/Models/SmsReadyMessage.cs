namespace SmsGatewayMM.Models;

record SmsReadyMessage(
    int Id,
    int VenueId,
    string SourceNumber,
    string DestinationNumber,
    string Content
);
