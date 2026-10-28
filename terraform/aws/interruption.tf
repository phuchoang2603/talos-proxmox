resource "aws_sqs_queue" "interruption" {
  name                      = "${var.cluster_name}-interruptions"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = local.tags
}
resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = {
    health    = { source = ["aws.health"], detail-type = ["AWS Health Event"] }
    spot      = { source = ["aws.ec2"], detail-type = ["EC2 Spot Instance Interruption Warning"] }
    rebalance = { source = ["aws.ec2"], detail-type = ["EC2 Instance Rebalance Recommendation"] }
    state     = { source = ["aws.ec2"], detail-type = ["EC2 Instance State-change Notification"] }
  }
  name          = "${var.cluster_name}-${each.key}"
  event_pattern = jsonencode(each.value)
  tags          = local.tags
}
resource "aws_cloudwatch_event_target" "interruption" {
  for_each = aws_cloudwatch_event_rule.interruption
  rule     = each.value.name
  arn      = aws_sqs_queue.interruption.arn
}
resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.interruption.arn
      Condition = { ArnEquals = { "aws:SourceArn" = [for rule in aws_cloudwatch_event_rule.interruption : rule.arn] } }
    }]
  })
}
resource "aws_iam_user_policy" "interruption" {
  name = "interruption-queue"
  user = aws_iam_user.karpenter.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"], Resource = aws_sqs_queue.interruption.arn }]
  })
}
