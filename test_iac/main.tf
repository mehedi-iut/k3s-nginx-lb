
resource "aws_vpc" "poridhi_vpc" {
  cidr_block = "10.10.0.0/16"
  tags = {
    Name = "test"
  }
}

resource "aws_subnet" "poridhi_subnet" {
  vpc_id            = aws_vpc.poridhi_vpc.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "test"
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.poridhi_vpc.id

  tags = {
    Name = "test"
  }
}

# resource "aws_internet_gateway_attachment" "gw_attachment" {
#     internet_gateway_id = aws_internet_gateway.gw.id
#     vpc_id              = aws_vpc.poridhi_vpc.id
# }

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.poridhi_vpc.id
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}


/* Route table associations */
resource "aws_route_table_association" "rt_association" {
  subnet_id      = aws_subnet.poridhi_subnet.id
  route_table_id = aws_route_table.public_rt.id
}


resource "aws_main_route_table_association" "public_rt" {
  vpc_id         = aws_vpc.poridhi_vpc.id
  route_table_id = aws_route_table.public_rt.id
}

# Allocate Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

# create security group rules for k3s
resource "aws_security_group" "k3s-sg" {
  name_prefix = "k3s-sg"
  vpc_id      = aws_vpc.poridhi_vpc.id
  description = "k3s security group"
}

resource "aws_security_group_rule" "ingress_rules" {
  for_each = {
    for port in var.sg_ports :
    port => port
  }
  type              = "ingress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s-sg.id
}


resource "aws_security_group_rule" "egress_rules" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = -1
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s-sg.id
}

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "example" {
  key_name   = "k3s-key-pair"
  public_key = tls_private_key.example.public_key_openssh
}

resource "local_file" "k3s-key" {
  content  = tls_private_key.example.private_key_pem
  filename = "k3s-key.pem"
}

resource "aws_instance" "public" {
  ami           = "ami-0c7217cdde317cfec"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.poridhi_subnet.id
  key_name      = "k3s-key-pair"
  security_groups = [
    aws_security_group.k3s-sg.id,
  ]
  depends_on = [aws_key_pair.example, tls_private_key.example, local_file.k3s-key]
}

resource "aws_eip" "public" {
  domain = "vpc"
}

resource "aws_eip_association" "public" {
  instance_id   = aws_instance.public.id
  allocation_id = aws_eip.public.id
}

########## private vm ##########
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.poridhi_vpc.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "test"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.poridhi_vpc.id
}


resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.poridhi_subnet.id

  tags = {
    Name = "gw NAT"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.gw]
}

# add route for nat gateway
resource "aws_route" "nat_gateway" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_rt_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_instance" "private" {
  ami           = "ami-0c7217cdde317cfec"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnet.id
  key_name      = "k3s-key-pair"
  security_groups = [
    aws_security_group.k3s-sg.id,
  ]
  depends_on = [aws_key_pair.example, tls_private_key.example, local_file.k3s-key]
}