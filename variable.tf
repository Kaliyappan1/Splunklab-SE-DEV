variable "key_name" {
  description = "Key pair name to use or create"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "storage_size" {
  description = "Root volume size"
  type        = number
}

variable "instance_name" {
  description = "Instance name tag"
  type        = string
}

variable "usermail" {
  description = "User email for tagging"
  type        = string
}

variable "quotahours" {
  description = "Run time quota in hours"
  type        = string
}

variable "category" {
  description = "Instance category"
  type        = string
}

variable "hoursperday" {
  description = "Instance hoursperday"
  type        = string
}

variable "planstartdate" {
  description = "Instance planstartdate"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
}

variable "market_type" {
  type    = string
  default = "on-demand"
}