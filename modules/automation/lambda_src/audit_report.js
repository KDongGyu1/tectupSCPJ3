const { CloudTrailClient, LookupEventsCommand } = require("@aws-sdk/client-cloudtrail");
const { ConfigServiceClient, GetComplianceSummaryByConfigRuleCommand } = require("@aws-sdk/client-config-service");
const { GuardDutyClient, ListDetectorsCommand } = require("@aws-sdk/client-guardduty");
const { SecurityHubClient, GetFindingsCommand } = require("@aws-sdk/client-securityhub");
const { SNSClient, PublishCommand } = require("@aws-sdk/client-sns");

const cloudTrail = new CloudTrailClient({});
const configService = new ConfigServiceClient({});
const guardDuty = new GuardDutyClient({});
const securityHub = new SecurityHubClient({});
const sns = new SNSClient({});

const SEVERITY = {
  NORMAL: 0,
  WARNING: 1,
  CRITICAL: 2,
};

const STATUS_LABEL = {
  NORMAL: "NORMAL",
  WARNING: "WARNING",
  CRITICAL: "CRITICAL",
};

exports.handler = async () => {
  const context = {
    projectName: process.env.PROJECT_NAME || "unknown",
    environment: process.env.ENVIRONMENT || "unknown",
    alertTopicArn: process.env.ALERT_TOPIC_ARN,
    generatedAt: new Date().toISOString(),
  };

  const checks = await Promise.all([
    checkCloudTrailLookup(),
    checkConfigSummary(),
    checkGuardDuty(),
    checkSecurityHub(),
  ]);

  const overallStatus = checks.reduce((current, check) => {
    return SEVERITY[check.status] > SEVERITY[current] ? check.status : current;
  }, "NORMAL");

  const report = {
    project: context.projectName,
    environment: context.environment,
    generatedAt: context.generatedAt,
    status: overallStatus,
    checks,
  };

  const message = renderReport(report);
  console.log(message);

  if (context.alertTopicArn) {
    await sns.send(new PublishCommand({
      TopicArn: context.alertTopicArn,
      Subject: `[${STATUS_LABEL[overallStatus]}] ${context.projectName} ${context.environment} monthly audit report`,
      Message: message,
    }));
  }

  return {
    statusCode: 200,
    body: JSON.stringify(report),
  };
};

async function checkCloudTrailLookup() {
  try {
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const response = await cloudTrail.send(new LookupEventsCommand({
      StartTime: since,
      MaxResults: 10,
    }));

    return {
      name: "CloudTrail lookup",
      status: "NORMAL",
      summary: `CloudTrail lookup succeeded. Recent events returned: ${response.Events?.length || 0}.`,
      evidence: {
        checkedSince: since.toISOString(),
      },
    };
  } catch (error) {
    return {
      name: "CloudTrail lookup",
      status: "CRITICAL",
      summary: "CloudTrail lookup failed. CloudTrail may be disabled, inaccessible, or blocked by IAM.",
      evidence: errorEvidence(error),
    };
  }
}

async function checkConfigSummary() {
  try {
    const response = await configService.send(new GetComplianceSummaryByConfigRuleCommand({}));
    const summary = response.ComplianceSummary || {};
    const compliant = summary.CompliantResourceCount?.CappedCount || 0;
    const nonCompliant = summary.NonCompliantResourceCount?.CappedCount || 0;

    return {
      name: "AWS Config summary",
      status: nonCompliant > 0 ? "WARNING" : "NORMAL",
      summary: `AWS Config summary succeeded. Compliant rules: ${compliant}, non-compliant rules: ${nonCompliant}.`,
      evidence: {
        compliantRules: compliant,
        nonCompliantRules: nonCompliant,
      },
    };
  } catch (error) {
    return {
      name: "AWS Config summary",
      status: "WARNING",
      summary: "AWS Config summary lookup failed. Config may be intentionally disabled for this account or environment.",
      evidence: errorEvidence(error),
    };
  }
}

async function checkGuardDuty() {
  try {
    const response = await guardDuty.send(new ListDetectorsCommand({}));
    const detectors = response.DetectorIds || [];

    return {
      name: "GuardDuty detector",
      status: detectors.length > 0 ? "NORMAL" : "WARNING",
      summary: detectors.length > 0
        ? `GuardDuty detector exists. Detector count: ${detectors.length}.`
        : "GuardDuty detector was not found.",
      evidence: {
        detectorCount: detectors.length,
      },
    };
  } catch (error) {
    return {
      name: "GuardDuty detector",
      status: "WARNING",
      summary: "GuardDuty detector lookup failed. GuardDuty may be disabled or unavailable in this account.",
      evidence: errorEvidence(error),
    };
  }
}

async function checkSecurityHub() {
  try {
    const response = await securityHub.send(new GetFindingsCommand({
      Filters: {
        RecordState: [{ Value: "ACTIVE", Comparison: "EQUALS" }],
        WorkflowStatus: [{ Value: "NEW", Comparison: "EQUALS" }],
      },
      MaxResults: 10,
    }));

    const findings = response.Findings || [];
    const highOrCritical = findings.filter((finding) => {
      const label = finding.Severity?.Label;
      return label === "HIGH" || label === "CRITICAL";
    }).length;

    return {
      name: "Security Hub findings",
      status: highOrCritical > 0 ? "CRITICAL" : findings.length > 0 ? "WARNING" : "NORMAL",
      summary: `Security Hub lookup succeeded. Active new findings sampled: ${findings.length}, high or critical: ${highOrCritical}.`,
      evidence: {
        sampledFindings: findings.length,
        highOrCriticalFindings: highOrCritical,
      },
    };
  } catch (error) {
    return {
      name: "Security Hub findings",
      status: "WARNING",
      summary: "Security Hub findings lookup failed. Security Hub may be intentionally disabled or not subscribed.",
      evidence: errorEvidence(error),
    };
  }
}

function renderReport(report) {
  const lines = [
    "# Monthly Security Audit Report",
    "",
    `Project: ${report.project}`,
    `Environment: ${report.environment}`,
    `GeneratedAt: ${report.generatedAt}`,
    `OverallStatus: ${STATUS_LABEL[report.status]}`,
    "",
    "## Check Results",
  ];

  for (const check of report.checks) {
    lines.push(
      "",
      `- ${check.name}: ${STATUS_LABEL[check.status]}`,
      `  Summary: ${check.summary}`,
      `  Evidence: ${JSON.stringify(check.evidence)}`,
    );
  }

  lines.push(
    "",
    "## Classification",
    "- NORMAL: Core audit checks completed and no high-risk finding was detected.",
    "- WARNING: Optional compliance tooling is disabled, unreachable, or returned non-critical issues.",
    "- CRITICAL: CloudTrail lookup failed or Security Hub returned high/critical active findings.",
  );

  return lines.join("\n");
}

function errorEvidence(error) {
  return {
    name: error?.name || "UnknownError",
    message: error?.message || "No error message returned",
  };
}
