exports.handler = async (event) => {
  return response("kyc", {
    decision: "review",
    controls: ["CDD", "EDD", "real-name-check"],
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
