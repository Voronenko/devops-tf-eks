TLDR...

https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html

Check variables - dependency on pre-existing pem key named EKS to access your worker instances for troubleshouting purposes

## Locals

```
  env = "${terraform.workspace}"

  availabilityzone = "${var.AWS_REGION}a"
  availabilityzone2 = "${var.AWS_REGION}b"

  cluster_name= "${local.env}-cluster"
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| AWS_ACCESS_KEY_ID |  | string | - | yes |
| AWS_REGION |  | string | - | yes |
| AWS_SECRET_ACCESS_KEY |  | string | - | yes |
| ec2_keyname | key used to access instances | string | `EKS` | no |
| private_subnet_cidr | CIDR for the Private Subnet | string | `10.11.1.0/24` | no |
| private_subnet_cidr2 | CIDR for the Private Subnet | string | `10.11.3.0/24` | no |
| public_subnet_cidr | CIDR for the Public Subnet | string | `10.11.0.0/24` | no |
| public_subnet_cidr2 | CIDR for the Public Subnet | string | `10.11.2.0/24` | no |
| vpc_cidr | CIDR for the whole VPC | string | `10.11.0.0/16` | no |

## Outputs

| Name | Description |
|------|-------------|
| config-map-aws-auth |  |
| kubeconfig |  |



Upon run you should see smth like

```
Apply complete! Resources: 36 added, 0 changed, 0 destroyed.

Outputs:
```

To make cluster fully operational, after provision you should: 

1) get cluster kubelet config via

```sh
make kubelet-config

terraform output kubeconfig > kubeconfig
export KUBECONFIG=/home/slavko/kubernetes/tf/kubeconfig
```

after that you should be able to execute commands over your eks cluster

```sh
kubectl get nodes
No resources found.
```

2) to allow nodes to join, you need to provide cluster with additional config map

```
make config-map-aws-auth 
terraform output config-map-aws-auth > config-map-aws-auth.yaml
kubectl apply -f config-map-aws-auth.yaml
configmap "aws-auth" created
kubectl get nodes --watch
NAME                         STATUS     ROLES     AGE       VERSION
ip-10-11-1-21.ec2.internal   NotReady   <none>    1s        v1.10.3
ip-10-11-3-220.ec2.internal   NotReady   <none>    0s        v1.10.3
...
ip-10-11-1-21.ec2.internal   Ready     <none>    31s       v1.10.3
ip-10-11-3-220.ec2.internal   Ready     <none>    31s       v1.10.3
```

3) You should be able to run pods and services

```
kubectl run  --image busybox pod-test --restart=Never
pod "pod-test" created
┌[tf]> 
└──➜ kubectl get pods
NAME       READY     STATUS      RESTARTS   AGE
pod-test   0/1       Completed   0          8s
```

Long story:

2BD
