exports.handler = async (event) => {
  return response("auth", {
    message: "Auth session helper. Cognito JWT authorizer handles API authorization.",
    required_mfa_roles: ["SettlementOperator", "OperationsAdmin", "SecurityAdmin", "Auditor"],
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
