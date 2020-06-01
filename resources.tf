resource "google_compute_network" "our_development_network" {
    name = "devopsnetwork"
    auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "dev-subnet" {
    ip_cidr_range = "10.10.1.0/24"
    name = "devopssubnet"
    region = "asia-southeast1"
    network = google_compute_network.our_development_network.id
}

resource "aws_vpc" "environment-example-two" {
    cidr_block = "10.10.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true
    tags = {
        Name = "terraform-aws-vpc-example-two"
    }
}

resource "aws_subnet" "subnet1" {
    cidr_block = "10.10.10.0/24"
    vpc_id = aws_vpc.environment-example-two.id
    availability_zone = "ap-southeast-1a"
}

resource "aws_subnet" "subnet2" {
    cidr_block = "10.10.20.0/24"
    vpc_id = aws_vpc.environment-example-two.id
    availability_zone = "ap-southeast-1b"
}

resource "aws_security_group" "subnetsecurity" {
    vpc_id = aws_vpc.environment-example-two.id

    ingress {
        cidr_blocks = [
            aws_vpc.environment-example-two.cidr_block
        ]
        
        from_port = 443
        to_port = 443
        protocol = "tcp"
    }
}

resource "azurerm_resource_group" "azy_network" {
    name = "devresgrp"
    location = "Southeast Asia"
}

resource "azurerm_virtual_network" "blue_virtual_network" {
    name = "bluevirtualnetwork1"
    location = azurerm_resource_group.azy_network.location
    resource_group_name = azurerm_resource_group.azy_network.name
    address_space = ["10.20.0.0/16"]
    dns_servers = ["10.20.0.4", "10.20.0.5"]

    subnet {
        name = "subnet2"
        address_prefix = "10.20.1.0/24"
    }

    tags = {
    environment = "Production"
    }
}