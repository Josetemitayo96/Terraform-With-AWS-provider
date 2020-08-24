
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "key_name" {
  default = "monday"
}

variable "aws_vpc_cidr_block" {
  default = "10.0.0.0/17"
}

variable "billing_code_tag" {

}

variable "environment_tag" {

}

variable "bucket_name" {

}

variable "availability_zone" {
  type = "map"
  default = {
    zone1 = "us-east-1b"
    zone2 = "us-east-1a"
  }
}
