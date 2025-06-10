variable "aws_region"       { default = "us-west-2" }
variable "aws_profile"      { default = "terraform" }
variable "public_key_path" {
    type    = string
    default = "~/.ssh/id_rsa.pub"
}
variable "vpc_id" {
    type        = string
    default     = ""
}