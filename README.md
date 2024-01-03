# Kubernetes with K3s and nginx

In this repo, I have created a Makefile to create 4 ec2 vm in AWS. 3 used for k3s and 1 for LoadBalancing with L7 nginx.
Among 3 k3s vm, one will be master and 2 will worker.

Request will come to LB VM and from that vm request will forwarded into any two of the worker vm where the pod is running the application

![plot](./k3s_with_nginx.png)



After running the **Makefile**, it will save **.pem** file and a **kubeconfig** file.
Using **.pem** file, we can access the vm using ssh and we can configure kubectl to point to our k3s cluster using kubeconfig.

