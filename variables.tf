variable "instance_type" {
  description = "Specify the instance type."
}


variable "ami" {
  description = "AMI IDs based on if node is a client or a server"

  default = "ami-0230ee9fd9ee23718"
}

variable "domain" {
  default     = "consul"
  description = "Domain of the Consul cluster"
}

variable "dcname" {
  description = "Datacenter name of the Consul cluster"
}

variable "region" {
  description = "Specify the prefered AWS region"
}

variable "IP" {
  type        = map(string)
  description = "IP segment based on if node is a server or a client."
}

variable "server_count" {
  description = "Count of Nomad servers in DC1."
  default     = "1"
}

variable "join_wan" {
  description = "Variable used to properly assign tags for auto join."
}

variable "token" {
  description = "Token for getting remote state"

}
