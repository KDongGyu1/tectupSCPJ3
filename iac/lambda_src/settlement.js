exports.handler = async (event) => {
  return response("settlement", {
    status: "CHANGE_ACCEPTED",
    audit_required: true,
    dispute_endpoint_configured: Boolean(process.env.DISPUTE_URL),
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
