exports.handler = async (event) => {
  return response("audit", {
    action: event.action ?? "lookup_events",
    worm_bucket: process.env.AUDIT_BUCKET_NAME,
    alert_topic_arn: process.env.ALERT_TOPIC_ARN,
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
