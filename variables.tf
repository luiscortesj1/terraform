variable "db_username" {
  type        = string
  description = "Username for RDS instance"
}

variable "db_password" {
  type        = string
  description = "Password for RDS instance"
  sensitive   = true
}
