exports.handler = async (event) => {
  return response("aml", {
    decision: "FLAG_IF_HIGH_RISK",
    reports: ["STR", "CTR"],
    fiu_endpoint_configured: Boolean(process.env.FIU_ENDPOINT_URL),
    regulation: process.env.REGULATION_SCOPE,
    request_id: event.requestContext?.requestId,
  });
};

function response(service, body) {
  return {
    statusCode: 200,
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ service, ...body }),
  };
}
