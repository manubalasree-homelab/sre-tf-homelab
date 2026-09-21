resource "local_file" "scope_marker" {
  filename = "${path.module}/scope-${var.account}-${var.environment}-${var.region}.txt"
  content  = "account=${var.account} environment=${var.environment} region=${var.region}\n"
}
