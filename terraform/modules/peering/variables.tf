# modules/peering/variables.tf
# Connects two VPCs with a peering link and installs return routes in both directions.
# Reused by every environment (dev/staging/prod), so it lives as a module. Each side is
# one object built from a vpc module's outputs.

variable "name" {
  description = "Name for the peering connection."
  type        = string
}

variable "requester" {
  description = "Requester VPC (id, cidr, and route table ids that need a route to the accepter)."
  type = object({
    vpc_id          = string
    cidr            = string
    route_table_ids = list(string)
  })
}

variable "accepter" {
  description = "Accepter VPC (id, cidr, and route table ids that need a route to the requester)."
  type = object({
    vpc_id          = string
    cidr            = string
    route_table_ids = list(string)
  })
}
