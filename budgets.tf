# Guardrails belong in the first apply, not a later one. Nothing should be able to spend before the
# alarm that watches spending exists — and billing is management-level, which is why these live in
# bootstrap rather than in platform-core with the rest of the observability work.

resource "aws_sns_topic" "billing_alerts" {
  name = "lakeworks-billing-alerts"
}

# Email is the starting point, not the destination. Email alerts get read on Monday and a runaway
# job needs to be read now, so this moves to a push endpoint once one exists.
resource "aws_sns_topic_subscription" "billing_email" {
  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Actual spend, at the steady-state target.
resource "aws_budgets_budget" "monthly_actual" {
  name         = "lakeworks-monthly-actual"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # No cost filter: the whole organization is lakeworks, so the account boundary separates spend
  # more accurately than a tag filter, which misses anything nobody tagged.

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.billing_alerts.arn]
  }
}

# Forecast, at double. This is the one that catches a runaway early — an actual-spend alarm fires
# after the money is gone, and a forecast alarm fires while the job is still running.
resource "aws_budgets_budget" "monthly_forecast" {
  name         = "lakeworks-monthly-forecast"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd * 2)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.billing_alerts.arn]
  }
}

# Catches a change in the *shape* of spend that a threshold misses — a new service appearing, or a
# cheap service becoming expensive while the total stays under budget.
#
# Gated because Cost Explorer is opt-in per account and cannot be enabled through the API. A fresh
# account rejects these with `User not enabled for cost explorer access`, and after opting in it
# takes up to 24 hours before the data backing an anomaly monitor exists. Flip the variable then.
resource "aws_ce_anomaly_monitor" "lakeworks" {
  count = var.enable_cost_anomaly_detection ? 1 : 0

  name              = "lakeworks-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "lakeworks" {
  count = var.enable_cost_anomaly_detection ? 1 : 0

  name      = "lakeworks-anomalies"
  frequency = "DAILY"

  monitor_arn_list = [aws_ce_anomaly_monitor.lakeworks[0].arn]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  # Absolute dollars, not a percentage. At this spend level a 200% anomaly is three dollars, and an
  # alert that fires on three dollars is an alert nobody reads.
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["10"]
    }
  }
}
