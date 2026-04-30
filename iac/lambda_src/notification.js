exports.handler = async (event) => {
  return response("notification", {
    channel: "sms-email",
    purpose: "consumer-protection-and-incident-alert",
    regulation: process.env.REGULATION_SCOPE,
    request_id: event.requestContext?.requestId,
  });
};

function response(service, body) {
  return {
    statusCode: 202,
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ service, ...body }),
  };
}
