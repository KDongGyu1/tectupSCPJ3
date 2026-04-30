exports.handler = async (event) => {
  const claims = event.requestContext?.authorizer?.jwt?.claims ?? {};
  return response("query", {
    scope: "role-scoped-transactions",
    subject: claims.sub ?? "anonymous",
    role: claims["custom:role"] ?? "unknown",
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
