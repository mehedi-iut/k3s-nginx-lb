SHELL := /bin/bash

VPC_CIDR ?= 10.10.0.0/16
SUBNET_CIDR ?= 10.10.1.0/24
KEY_PAIR_NAME ?= poridhi
SECURITY_GROUP_NAME ?= poridhi
WORKER_COUNT = 2
AWS_DEFAULT_REGION = us-east-1

aws-vars:
ifndef AWS_DEFAULT_REGION
	$(error AWS_DEFAULT_REGION is not set)
else ifndef VPC_CIDR
	$(error VPC_CIDR is not set)
endif

### Get Targets ###
get-vpc-id-by-tag-%: aws-vars
	$(eval VPC_ID := $(shell aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$*" | jq -r '.Vpcs[].VpcId'))

get-subnet-id-by-tag-%: aws-vars
	$(eval SUBNET_ID := $(shell aws ec2 describe-subnets --filters "Name=tag:Name,Values=$*" | jq -r '.Subnets[].SubnetId'))

get-igw-id-by-tag-%: aws-vars
	$(eval IGW_ID := $(shell aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=$*" | jq -r '.InternetGateways[].InternetGatewayId'))

get-igw-attachment-state-by-tag-%: aws-vars
	$(eval IGW_ATTACH_STATE := $(shell aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=$*" | jq -r '.InternetGateways[].Attachments[].State'))

get-route-table-id-by-tag-%: aws-vars
	$(eval ROUTE_TABLE_ID := $(shell aws ec2 describe-route-tables --filters "Name=tag:Name,Values=$*" | jq -r '.RouteTables[].RouteTableId'))

get-route-table-association-id-by-tag-%: aws-vars
	$(eval ROUTE_TABLE_ASSOCIATION_ID := $(shell aws ec2 describe-route-tables --filters "Name=tag:Name,Values=$*" | jq -r '.RouteTables[].Associations[].RouteTableAssociationId'))

get-security-group-id-by-tag-%: aws-vars
	$(eval SECURITY_GROUP_ID := $(shell aws ec2 describe-security-groups --filters "Name=group-name,Values=$(SECURITY_GROUP_NAME)" --query "SecurityGroups[0].GroupId" --output text))

get-master-ip-by-tag: aws-vars
	$(eval MASTER_IP := $(shell aws ec2 describe-instances --filters "Name=tag:Name,Values=k3s-master" --query "Reservations[].Instances[].PublicIpAddress" --output text))

### Create Targets ###

create-vpc-%: aws-vars get-vpc-id-by-tag-%
	@if [[ -z "$(VPC_ID)" ]]; then \
		echo "Creating VPC with CIDR $(VPC_CIDR) and tag: $*" && \
		VPC_ID=$$(aws ec2 create-vpc --cidr-block $(VPC_CIDR) | jq -r .Vpc.VpcId) && \
		aws ec2 create-tags --resources $${VPC_ID} --tags Key=Name,Value=$* && \
		aws ec2 modify-vpc-attribute --vpc-id $${VPC_ID} --enable-dns-support '{"Value": true}' && \
		aws ec2 modify-vpc-attribute --vpc-id $${VPC_ID} --enable-dns-hostnames '{"Value": true}' ; \
	else \
		echo "VPC with CIDR $(VPC_CIDR) and tag '$*' already exists." ; \
	fi

create-subnet-%: aws-vars get-subnet-id-by-tag-% get-vpc-id-by-tag-%
	@if [[ -z "$(VPC_ID)" ]]; then echo "ERROR: VPC with tag '$*' not found, create it with: make create-vpc-$*" ; exit 1 ; fi
	@if [[ -z "$(SUBNET_ID)" ]]; then \
		echo "Creating Subnet with CIDR $(SUBNET_CIDR) in VPC $(VPC_ID) and tag: $*" && \
		SUBNET_ID=$$(aws ec2 create-subnet --vpc-id $(VPC_ID) --cidr-block $(SUBNET_CIDR) | jq -r '.Subnet.SubnetId') && \
		aws ec2 create-tags --resources $${SUBNET_ID} --tags Key=Name,Value=$* ; \
	else \
		echo "Subnet with tag '$*' already exists." ; \
	fi

create-igw-%: aws-vars get-igw-id-by-tag-%
	@if [[ -z "$(IGW_ID)" ]]; then \
		echo "Creating IGW with tag: $*" && \
		INTERNET_GATEWAY_ID=$$(aws ec2 create-internet-gateway | jq -r '.InternetGateway.InternetGatewayId') && \
		aws ec2 create-tags --resources $${INTERNET_GATEWAY_ID} --tags Key=Name,Value=$* ; \
	else \
		echo "Internet Gateway with tag '$*' already exists." ; \
	fi

attach-igw-%: aws-vars get-igw-id-by-tag-% get-vpc-id-by-tag-% get-igw-attachment-state-by-tag-%
	@if [[ -z "$(IGW_ID)" ]]; then echo "ERROR: Internet Gateway with tag '$*' not found, create it with: make create-igw-$*" ; exit 1; fi
	@if [[ -z "$(VPC_ID)" ]]; then echo "ERROR: VPC with tag '$*' not found, create it with: make create-vpc-$*" ; exit 1 ; fi
	@if [[ -z "$(IGW_ATTACH_STATE)" ]]; then \
		echo "Attaching IGW $(IGW_ID) to VPC $(VPC_ID)" && \
		aws ec2 attach-internet-gateway --internet-gateway-id $(IGW_ID) --vpc-id $(VPC_ID) ; \
	else \
		echo "Internet Gateway $(IGW_ID) is already attached" ; \
	fi

create-route-table-%: aws-vars get-route-table-id-by-tag-% get-vpc-id-by-tag-%
	@if [[ -z "$(VPC_ID)" ]]; then echo "ERROR: VPC with tag '$*' not found, create it with: make create-vpc-$*" ; exit 1 ; fi
	@if [[ -z "$(ROUTE_TABLE_ID)" ]]; then \
		echo "Creating Route Table in VPC $(VPC_ID) with tag: $*" && \
		ROUTE_TABLE_ID=$$(aws ec2 create-route-table --vpc-id $(VPC_ID) | jq -r '.RouteTable.RouteTableId') && \
		aws ec2 create-tags --resources $${ROUTE_TABLE_ID} --tags Key=Name,Value=$* ; \
	else \
		echo "Route Table with tag '$*' already exists." ; \
	fi

associate-route-table-%: aws-vars get-route-table-id-by-tag-% get-subnet-id-by-tag-% get-route-table-association-id-by-tag-%
	@if [[ -z "$(ROUTE_TABLE_ID)" ]]; then echo "ERROR: Route Table with tag '$*' not found, create it with: make create-route-table-$*" ; exit 1; fi
	@if [[ -z "$(SUBNET_ID)" ]]; then echo "ERROR: Subnet with tag '$*' not found, create it with: make create-subnet-$*" ; exit 1; fi
	@if [[ -z "$(ROUTE_TABLE_ASSOCIATION_ID)" ]]; then \
		echo "Associating route table $(ROUTE_TABLE_ID) with subnet $(SUBNET_ID)" && \
		aws ec2 associate-route-table --route-table-id $(ROUTE_TABLE_ID) --subnet-id $(SUBNET_ID) ; \
	else \
		echo "Route Table $(ROUTE_TABLE_ID) already associated with subnet $(SUBNET_ID)" ; \
	fi

create-route-to-igw-%: get-route-table-id-by-tag-% get-igw-id-by-tag-%
	@if [[ -z "$(ROUTE_TABLE_ID)" ]]; then echo "ERROR: Route Table with tag '$*' not found, create it with: make create-route-table-$*" ; exit 1; fi
	@if [[ -z "$(IGW_ID)" ]]; then echo "ERROR: Internet Gateway with tag '$*' not found, create it with: make create-igw-$*" ; exit 1; fi
	aws ec2 create-route --route-table-id $(ROUTE_TABLE_ID) --destination-cidr-block 0.0.0.0/0 --gateway-id $(IGW_ID)


create-key-pair: aws-vars
	@echo "Creating Key Pair: $(KEY_PAIR_NAME)"
	@aws ec2 create-key-pair --key-name $(KEY_PAIR_NAME) --query 'KeyMaterial' --output text > $(KEY_PAIR_NAME).pem
	@chmod 400 $(KEY_PAIR_NAME).pem


create-security-group-%: aws-vars get-vpc-id-by-tag-%
	@echo "Creating Security Group: $(SECURITY_GROUP_NAME)"
	$(eval SECURITY_GROUP_ID := $(shell aws ec2 create-security-group --group-name $(SECURITY_GROUP_NAME) --description "My security group" --vpc-id $(VPC_ID) --output text --query 'GroupId'))
	@aws ec2 authorize-security-group-ingress --group-id $(SECURITY_GROUP_ID) --protocol tcp --port 2379-2380 --cidr 0.0.0.0/0
	@aws ec2 authorize-security-group-ingress --group-id $(SECURITY_GROUP_ID) --protocol tcp --port 6443 --cidr 0.0.0.0/0
	@aws ec2 authorize-security-group-ingress --group-id $(SECURITY_GROUP_ID) --protocol udp --port 8472 --cidr 0.0.0.0/0
	@aws ec2 authorize-security-group-ingress --group-id $(SECURITY_GROUP_ID) --protocol tcp --port 10250 --cidr 0.0.0.0/0
	@aws ec2 authorize-security-group-ingress --group-id $(SECURITY_GROUP_ID) --protocol udp --port 51820 --cidr 0.0.0.0/0
	@aws ec2 authorize-security-group-ingress --group-id $(SECURITY_GROUP_ID) --protocol udp --port 51821 --cidr 0.0.0.0/0
	@aws ec2 authorize-security-group-ingress --group-id $(SECURITY_GROUP_ID) --protocol tcp --port 22 --cidr 0.0.0.0/0
	@aws ec2 authorize-security-group-ingress --group-id $(SECURITY_GROUP_ID) --protocol tcp --port 30000-32767 --cidr 0.0.0.0/0
	@aws ec2 authorize-security-group-ingress --group-id $(SECURITY_GROUP_ID) --protocol tcp --port 80 --cidr 0.0.0.0/0



create-instances-%: aws-vars get-security-group-id-by-tag-% get-subnet-id-by-tag-%
	@for i in $(shell seq 1 $(WORKER_COUNT)); do \
    	aws ec2 run-instances --image-id ami-0c7217cdde317cfec --count 1 \
       	--tag-specifications "[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"k3s-worker-$$i\"}]}]" \
       	--instance-type t2.medium --key-name $(KEY_PAIR_NAME) \
       	--security-group-ids $(SECURITY_GROUP_ID) \
       	--subnet-id $(SUBNET_ID) \
       	--associate-public-ip-address; \
	done

	@aws ec2 run-instances --image-id ami-0c7217cdde317cfec --count 1 \
     --tag-specifications "[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"k3s-master\"}]}]" \
     --instance-type t2.medium --key-name $(KEY_PAIR_NAME) --security-group-ids $(SECURITY_GROUP_ID) \
     --subnet-id $(SUBNET_ID) \
     --associate-public-ip-address;

	@aws ec2 run-instances --image-id ami-0c7217cdde317cfec --count 1 \
     --tag-specifications "[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"lb\"}]}]" \
     --instance-type t2.micro --key-name $(KEY_PAIR_NAME) --security-group-ids $(SECURITY_GROUP_ID) \
     --subnet-id $(SUBNET_ID) \
     --associate-public-ip-address;


check-master-ip: get-master-ip-by-tag
	@echo $(MASTER_IP)

install-k3s-master: get-master-ip-by-tag
	@INSTANCE_IDS=$$(aws ec2 describe-instances --region $(AWS_DEFAULT_REGION) --filters "Name=tag:Name,Values=k3s-master" --query 'Reservations[*].Instances[*].InstanceId' --output text); \
	INSTANCE_STATE=$$(aws ec2 describe-instance-status --region $(AWS_DEFAULT_REGION) --instance-ids $$INSTANCE_IDS --query 'InstanceStatuses[*].InstanceState.Name' --output text); \
	echo $(AWS_DEFAULT_REGION); \
	echo $$INSTANCE_IDS; \
	echo $$INSTANCE_STATE; \
	\
	while [ "$$INSTANCE_STATE" != "running" ]; do \
        echo "Waiting for EC2 instances to be in running state..."; \
        sleep 10; \
        INSTANCE_STATE=$$(aws ec2 describe-instance-status --region $(AWS_DEFAULT_REGION) --instance-ids $$INSTANCE_IDS --query 'InstanceStatuses[*].InstanceState.Name' --output text); \
    done; \
	echo "EC2 is running"
	@ssh -i $(KEY_PAIR_NAME).pem ubuntu@$(MASTER_IP) "sudo ufw disable && curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--write-kubeconfig=/home/ubuntu/.kube/config --write-kubeconfig-mode=644' sh - "

get-token: get-master-ip-by-tag install-k3s-master
	@ssh -i $(KEY_PAIR_NAME).pem ubuntu@$(MASTER_IP) 'sudo cat /var/lib/rancher/k3s/server/node-token' > token.txt
	@K3S_TOKEN=$$(cat token.txt)

read-text:
	# TOKEN=$$(cat token.txt); \
	# echo "Token value is: $$TOKEN";
	$(eval TOKEN := $(shell cat token.txt))
	@echo "Token is: $(TOKEN) " 

sleep-2-min:
	@echo "Let the security group rule propagate"
	@sleep 120

install-worker-2: aws-vars get-master-ip-by-tag
	@K3S_TOKEN=$$(ssh -i $(KEY_PAIR_NAME).pem ubuntu@$(MASTER_IP) 'sudo cat /var/lib/rancher/k3s/server/node-token'); \
	echo "The token is: $$K3S_TOKEN"; \
	for i in $$(seq 1 $(WORKER_COUNT)); do \
		WORKER_IP=$$(aws ec2 describe-instances --filters "Name=tag:Name,Values=k3s-worker-$$i" --query "Reservations[].Instances[].PublicIpAddress" --output text); \
		echo "The Worker-node-$$i: $$WORKER_IP"; \
		ssh -i $(KEY_PAIR_NAME).pem ubuntu@$$WORKER_IP "sudo ufw disable && curl -sfL https://get.k3s.io | K3S_URL=https://$(MASTER_IP):6443 K3S_TOKEN=$$K3S_TOKEN sh -s -"; \
	done


reboot-master:
	@INSTANCE_IDS=$$(aws ec2 describe-instances --region $(AWS_DEFAULT_REGION) --filters "Name=tag:Name,Values=k3s-master" --query 'Reservations[*].Instances[*].InstanceId' --output text); \
	aws ec2 reboot-instances --instance-ids $$INSTANCE_IDS

associate-elastic-ip-lb: aws-vars
	@ELASTIC_IP_LB=$$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text); \
	LB_INSTANCE_ID=$$(aws ec2 describe-instances --region $(AWS_DEFAULT_REGION) --filters "Name=tag:Name,Values=lb" --query 'Reservations[*].Instances[*].InstanceId' --output text); \
	aws ec2 associate-address --instance-id $$LB_INSTANCE_ID --allocation-id $$ELASTIC_IP_LB;

create-aws-resources-%:
	make create-vpc-$*
	make create-subnet-$*
	make create-igw-$*
	make attach-igw-$*
	make create-route-table-$*
	make create-route-to-igw-$*
	make associate-route-table-$*
	make create-key-pair
	make create-security-group-$*
	make create-instances-$*
	make sleep-2-min
	make install-k3s-master
	make install-worker-2
	make reboot-master
	make associate-elastic-ip-lb