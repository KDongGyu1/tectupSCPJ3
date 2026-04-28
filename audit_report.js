const { SNSClient, PublishCommand } = require("@aws-sdk/client-sns");

exports.handler = async () => {
  const sns = new SNSClient({});
  const message = {
    project: process.env.PROJECT_NAME,
    environment: process.env.ENVIRONMENT,
    report_type: "monthly-compliance-summary",
    controls: [
      "VPC tier separation",
      "CloudTrail and VPC Flow Logs",
      "S3 Object Lock",
      "RDS encryption and backup",
      "Security Hub and GuardDuty",
      "MFA-required admin roles",
    ],
    generated_at: new Date().toISOString(),
  };

  if (process.env.ALERT_TOPIC_ARN) {
    await sns.send(
      new PublishCommand({
        TopicArn: process.env.ALERT_TOPIC_ARN,
        Subject: "FinPay monthly compliance report",
        Message: JSON.stringify(message, null, 2),
      }),
    );
  }

  return {
    statusCode: 200,
    body: JSON.stringify(message),
  };
};

