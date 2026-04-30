exports.handler = async (event) => {
  return response("payment", {
    transaction_id: `TX-${Date.now()}`,
    status: "PENDING",
    sensitive_data: "encrypted-reference-only",
    event_queue_url: process.env.EVENT_QUEUE_URL,
    pg_endpoint_configured: Boolean(process.env.PG_ENDPOINT_URL),
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
