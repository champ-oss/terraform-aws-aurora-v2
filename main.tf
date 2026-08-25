data "aws_region" "this" {}

resource "random_id" "this" {
  byte_length = 3
}
