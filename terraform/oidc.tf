variable "github_repo" {
  description = "GitHub repo allowed to deploy (owner/name)"
  type        = string
  default     = "basitol/example-voting-app"
}

variable "github_oidc_subject" {
  description = "Exact OIDC subject GitHub sends for this repo's main branch"
  type        = string
  default     = "repo:basitol@41623944/example-voting-app@1438720249:ref:refs/heads/main"
}

# Lets AWS trust logins that come from GitHub Actions
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# The role GitHub Actions uses. Only pushes to main on your repo can use it.
resource "aws_iam_role" "github_deploy" {
  name = "${var.cluster_name}-github-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = var.github_oidc_subject
        }
      }
    }]
  })
}

# Lets the role look up the cluster address
resource "aws_iam_role_policy" "github_deploy_eks" {
  name = "describe-cluster"
  role = aws_iam_role.github_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = aws_eks_cluster.voting_app.arn
    }]
  })
}

# Lets the role deploy inside the cluster (default namespace only)
resource "aws_eks_access_entry" "github_deploy" {
  cluster_name  = aws_eks_cluster.voting_app.name
  principal_arn = aws_iam_role.github_deploy.arn
}

resource "aws_eks_access_policy_association" "github_deploy" {
  cluster_name  = aws_eks_cluster.voting_app.name
  principal_arn = aws_iam_role.github_deploy.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["default"]
  }

  depends_on = [aws_eks_access_entry.github_deploy]
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}
