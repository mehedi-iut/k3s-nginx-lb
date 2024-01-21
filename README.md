# Kubernetes with K3s and nginx

In this repo, I have created a Makefile to create 4 ec2 vm in AWS. 3 used for k3s and 1 for LoadBalancing with L7 nginx.
Among 3 k3s vm, one will be master and 2 will worker.

### Important
when configure aws using ```aws configure``` then output format must be **json**, otherwise **Makefile** will not work

Request will come to LB VM and from that vm request will forwarded into any two of the worker vm where the pod is running the application

![plot](./k3s_with_nginx.png)



After running the **Makefile**, it will save **.pem** file
Using **.pem** file, we can access the vm using ssh and we can configure kubectl to point to our k3s cluster using kubeconfig.

### kubeconfig
To get the kubeconfig, ssh into the k3s master vm. then run the below command
```bash
sudo cat /etc/rancher/k3s/k3s.yaml
```

now copy the output and in your local machine, create **.kube** folder in home directory. if it already exists then no need to create the folder
* for linux the location is ```/home/<user-name>```
* for windows the location is ```C:\Users\<user-name>```

inside the **.kube** folder create file name **config**, if it already exists, then no need to create it.

paste the copied text from k3s master to config file sothat kubectl can talk to master. if **config** file contains other cluster information, then added the content accordingly without override it

### issue

you may get certificate validation error, in that case you need to add **kubectl --insecure-skip-tls-verify** and run the command. for example
```bash
kubectl --insecure-skip-tls-verify get nodes
```

### Deploy demo app
To Deploy our demo app, just navigate to **manifests** folder and run
```bash
kubectl --insecure-skip-tls-verify apply -f .
```

it will create two deployment object and two nodeport service
in **/** we will get nginx welcome page and in **/api** we will see message **Hello Kubernetes**


### LB

Now, we need to ssh into LB ec2 vm and install docker to run the nginx container
```bash
sudo apt update
sudo apt install docker.io
```

then create a **Dockerfile** with below content
```Dockerfile
FROM nginx:latest

COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

CMD [ "nginx", "-g", "daemon off;" ]
```

and **nginx.conf**, must change the **upstream** block with worker vm private ip and yours service nodePort
```lua
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    log_format main '$proxy_add_x_forwarded_for - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log debug;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        listen 80;
        server_name _;

        location /api {
            proxy_pass http://backend_api;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location / {
            proxy_pass http://backend_fr;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }


    upstream backend_api {
        # port must be backend_api service nodeport
        server 10.10.1.214:30180 weight=1 max_fails=3 fail_timeout=30s;
        server 10.10.1.105:30180 weight=1 max_fails=3 fail_timeout=30s;
        # Add more backend servers if needed
    }

    upstream backend_fr {
        # port must be fr-service node port
        server 10.10.1.214:30170 weight=1 max_fails=3 fail_timeout=30s;
        server 10.10.1.105:30170 weight=1 max_fails=3 fail_timeout=30s;
        # Add more backend servers if needed
    }
}

```


After that in lb vm, create docker image and run it
```bash
sudo docker image build -t my-nginx .
sudo docker run -d -p 80:80 my-nginx
```

After that we you hit lb public ip to get response
```http://<public-ip>``` for nginx response
```http://<public-ip>/api``` for getting Hello message from golang service
