tf_dev_init:
	@ echo "Initializing terraform...."
	@ cd env/dev
	@ terraform fmt -recursive
	@ terraform init

tf_dev_plan:
	@ echo "Planning terraform..."
	@ cd env/dev
	@ terraform plan

tf_dev_apply:
	@ echo "Applying terraform..."
	@ cd env/dev
	@ terraform apply -auto-approve

tf_dev_destroy:
	@ echo "Destroying terraform..."
	@ cd env/dev
	@ terraform destroy -auto-approve