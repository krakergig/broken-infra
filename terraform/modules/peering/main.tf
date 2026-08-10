# modules/peering/main.tf
# VPC peering connection + routes so the two VPCs can communicate (challenge req #2).

resource "aws_vpc_peering_connection" "this" {
  vpc_id      = var.requester.vpc_id
  peer_vpc_id = var.accepter.vpc_id
  auto_accept = true # same account + region

  tags = { Name = var.name }
}

# Requester-side route tables -> accepter CIDR.
resource "aws_route" "requester_to_accepter" {
  count = length(var.requester.route_table_ids)

  route_table_id            = var.requester.route_table_ids[count.index]
  destination_cidr_block    = var.accepter.cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

# Accepter-side route tables -> requester CIDR.
resource "aws_route" "accepter_to_requester" {
  count = length(var.accepter.route_table_ids)

  route_table_id            = var.accepter.route_table_ids[count.index]
  destination_cidr_block    = var.requester.cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}
