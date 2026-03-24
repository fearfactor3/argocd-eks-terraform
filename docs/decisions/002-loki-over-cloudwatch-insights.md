# ADR-002: Loki over CloudWatch Insights for Log Querying

**Status**: Accepted

---

## Context

VPC flow logs are captured to CloudWatch Logs (the only supported AWS-native destination alongside S3 and Kinesis Firehose). The question is how they should be queried and visualised.

Two approaches were considered:

| Approach | How it works |
|---|---|
| **CloudWatch Insights** | Query logs directly in CloudWatch using the Insights query language. Visualise in the CloudWatch console or a Grafana CloudWatch datasource. |
| **Loki + Grafana** | Ship logs from CloudWatch to Loki via Grafana Alloy. Query in Grafana using LogQL. |

---

## Decision

Ship logs to **Loki** and query via **Grafana**.

---

## Reasons

### Unified observability surface

Prometheus and Grafana are already deployed in the cluster for metrics. Routing logs to Loki means metrics (Prometheus), logs (Loki), and alerts (Alertmanager) are all accessible in the same Grafana instance under the same dashboards. CloudWatch Insights is a separate UI with a separate query language — switching between it and Grafana breaks the workflow.

### LogQL vs CloudWatch Insights query language

LogQL is the same query language used for all Loki log sources. It is also the basis for Grafana's unified query model. CloudWatch Insights uses a bespoke SQL-like syntax that is specific to AWS and not transferable. For learning purposes, LogQL investment carries over to any Loki deployment regardless of cloud provider.

### Cost model

CloudWatch Insights charges per gigabyte of data scanned per query. For exploratory queries or dashboards that refresh frequently, costs can accumulate. Loki with filesystem storage (SingleBinary mode) has no per-query cost once the infrastructure is running.

### Correlation with cluster logs

In a future state, Alloy can be extended to also collect Kubernetes pod logs and ship them to the same Loki instance. This makes it possible to correlate network-level flow log events with application-level log events in a single Grafana explore view. CloudWatch Insights cannot correlate across log groups without complex cross-log-group queries.

---

## Trade-offs

- **Operational overhead**: Running Loki adds a stateful component to the cluster. SingleBinary mode with filesystem storage is simple but not highly available — a pod restart loses in-flight data until the next Alloy poll cycle.
- **Additional pipeline complexity**: Flow logs cannot go directly to Loki. CloudWatch is a required intermediate destination, and Alloy must run continuously to forward them. If Alloy goes down, logs accumulate in CloudWatch but are not forwarded until it recovers (within the CloudWatch retention window).
- **Not production-ready as-is**: SingleBinary mode with filesystem storage is appropriate for this test instance. A production Loki deployment should use distributed mode backed by S3 object storage with separate read, write, and backend components.

---

## Migration path (if needed)

To switch back to CloudWatch Insights:

1. Remove the Loki and Alloy Helm releases from `stacks/prometheus/main.tf`
2. Remove the `additionalDataSources` Loki entry from the Grafana values
3. Add a CloudWatch datasource to Grafana pointing at the flow logs log group
4. The CloudWatch log group and flow log IAM resources in the network module remain unchanged
