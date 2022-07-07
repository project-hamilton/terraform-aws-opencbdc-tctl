locals {
  name = "testresults"
  tags = var.tags
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


###################
### Open Search ###
###################
resource "aws_opensearch_domain" "this" {
  domain_name    = "${var.environment}-${local.name}"
  engine_version = var.opensearch_engine_version

  encrypt_at_rest {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  cluster_config {
    instance_type  = var.opensearch_instance_type
    instance_count = var.opensearch_instance_count
  }

  ebs_options {
    ebs_enabled = true
    volume_type = var.opensearch_ebs_volume_type
    volume_size = var.opensearch_ebs_volume_size
  }

  advanced_security_options {
    enabled = true
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch.arn
    log_type                 = "INDEX_SLOW_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch.arn
    log_type                 = "SEARCH_SLOW_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch.arn
    log_type                 = "ES_APPLICATION_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch.arn
    log_type                 = "AUDIT_LOGS"
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "opensearch" {
  name = "/aws/OpenSearchService/domains/${local.name}"
}

resource "aws_cloudwatch_log_resource_policy" "example" {
  policy_name = "OpenSearchService-${local.name}"

  policy_document = <<CONFIG
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "es.amazonaws.com"
      },
      "Action": [
        "logs:PutLogEvents",
        "logs:PutLogEventsBatch",
        "logs:CreateLogStream"
      ],
      "Resource": "arn:aws:logs:*"
    }
  ]
}
CONFIG
}


################
### Firehose ###
################
resource "aws_kinesis_firehose_delivery_stream" "this" {
  name        = "${var.environment}-${local.name}"
  destination = "elasticsearch"

  elasticsearch_configuration {
    domain_arn = aws_opensearch_domain.this.arn
    role_arn   = aws_iam_role.firehose.arn
    index_name = local.name
    type_name  = local.name
  }
}

resource "aws_iam_role" "firehose" {
  name = "firehose-${var.environment}-${local.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      },
    ]
  })

  tags = local.tags
}

resource "aws_iam_policy" "policy" {
  name        = "KinesisFirehoseServiceRole-${local.name}-${data.aws_region.current.name}-1657054991552"
  path        = "/"
  description = "Access for Kinesis Firehose to Opensearch"
  policy      = data.aws_iam_policy_document.firehose.json
}

data "aws_iam_policy_document" "firehose" {
  statement {
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject"
    ]
    resources =  [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "es:DescribeElasticsearchDomain",
      "es:DescribeElasticsearchDomains",
      "es:DescribeElasticsearchDomainConfig",
      "es:ESHttpPost",
      "es:ESHttpPut"
    ]
    resources = [
      "${aws_opensearch_domain.this.arn}",
      "${aws_opensearch_domain.this.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "es:ESHttpGet"
    ]
    resources = [
       "${aws_opensearch_domain.this.arn}/_all/_settings",
       "${aws_opensearch_domain.this.arn}/_cluster/stats",
       "${aws_opensearch_domain.this.arn}/${local.name}/_mapping/*",
       "${aws_opensearch_domain.this.arn}/_nodes",
       "${aws_opensearch_domain.this.arn}/_nodes/*/stats",
       "${aws_opensearch_domain.this.arn}/_nodes/_stats",
       "${aws_opensearch_domain.this.arn}/${local.name}/_stats",
    ]
  }
}

##########
### S3 ###
##########
# Test outputs S3 Bucket
resource "aws_s3_bucket" "this" {
  bucket        = "${data.aws_caller_identity.current.account_id}-firehose-backup"
  force_destroy = true

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "AES256"
      }
    }
  }

  tags = local.tags
}
