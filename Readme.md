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

# First step is creating a VPC with Public and Private Subnets for Your Amazon EKS Cluster

The simpliest VPC would be all subnets public, like seen on cloud template
( https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/amazon-eks-vpc-sample.yaml )

But if your goal is to reuse that in a production, the reasonable would be VPC with
private and public parts, like  https://docs.aws.amazon.com/eks/latest/userguide/create-public-private-vpc.html


## Step 1.1: Create an Elastic IP Address for Your NAT Gateway(s)

Worker nodes in private subnets require a NAT gateway for outbound internet access. A NAT gateway requires an Elastic IP address in your public subnet, but the VPC wizard does not create one for you. Create the Elastic IP address before running the VPC wizard.

To create an Elastic IP address

    Open the Amazon VPC console at https://console.aws.amazon.com/vpc/.

    In the left navigation pane, choose Elastic IPs.

    Choose Allocate new address, Allocate, Close.

    Note the Allocation ID for your newly created Elastic IP address; you enter this later in the VPC wizard.

```tf

resource "aws_eip" "nat_eip" {
  vpc = true
}

```


## Step 1.2: Run the VPC Wizard

The VPC wizard automatically creates and configures most of your VPC resources for you.

To run the VPC wizard

    In the left navigation pane, choose VPC Dashboard.

    Choose Start VPC Wizard, VPC with Public and Private Subnets, Select.

    For VPC name, give your VPC a unique name.

    For Elastic IP Allocation ID, choose the ID of the Elastic IP address that you created earlier.

    Choose Create VPC.

    When the wizard is finished, choose OK. Note the Availability Zone in which your VPC subnets were created. Your additional subnets should be created in a different Availability Zone.


Appropriate terraform part would be

```tf

// create vpc
resource "aws_vpc" "default" {
  cidr_block = "${var.vpc_cidr}"
  enable_dns_hostnames = true
  tags {
    Name = "eks-vpc"
  }
}

// public subnet
resource "aws_subnet" "eks-public" {
  vpc_id = "${aws_vpc.default.id}"

  cidr_block = "${var.public_subnet_cidr}"
  availability_zone = "${var.AWS_REGION}a"

  tags {
    Name = "eks-public"
  }
}


// private subnet
resource "aws_subnet" "eks-private" {
  vpc_id = "${aws_vpc.default.id}"

  cidr_block = "${var.private_subnet_cidr}"
  availability_zone = "${var.AWS_REGION}a"

  tags {
    Name = "eks-private"
  }
}


// internet gateway, note: creation takes a while

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.default.id}"
}



// reserve elastic ip for nat gateway

resource "aws_eip" "nat_eip" {
  vpc = true
}

// create nat once internet gateway created
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = "${aws_eip.nat_eip.id}"
  subnet_id = "${aws_subnet.eks-public.id}"
  depends_on = ["aws_internet_gateway.igw"]
}

//Create private route table and the route to the internet
//This will allow all traffics from the private subnets to the internet through the NAT Gateway (Network Address Translation)

resource "aws_route_table" "private_route_table" {
  vpc_id = "${aws_vpc.default.id}"
  tags {
    Name = "Private route table"
  }
}

resource "aws_route" "private_route" {
  route_table_id  = "${aws_route_table.private_route_table.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = "${aws_nat_gateway.nat_gateway.id}"
}

resource "aws_route_table" "eks-public" {
  vpc_id = "${aws_vpc.default.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags {
    Name = "eks-public"
  }
}

// associate route tables

resource "aws_route_table_association" "eks-public" {
  subnet_id = "${aws_subnet.eks-public.id}"
  route_table_id = "${aws_route_table.eks-public.id}"
}

resource "aws_route_table_association" "eks-private" {
  subnet_id = "${aws_subnet.eks-private.id}"
  route_table_id = "${aws_route_table.private_route_table.id}"
}


```


# Step 2 create your Amazon EKS service role

    Open the IAM console at https://console.aws.amazon.com/iam/.

    Choose Roles, then Create role.

    Choose EKS from the list of services, then Allows Amazon EKS to manage your clusters on your behalf for your use case, then Next: Permissions.

    Choose Next: Review.

    For Role name, enter a unique name for your role, such as eksServiceRole, then choose Create role.



Terraform definition for the role goes as below.

```tf

    resource "aws_iam_role" "EKSClusterRole" {
      name = "EKSClusterRole",
      description = "Allows EKS to manage clusters on your behalf.",
      assume_role_policy = <<EOF
    {
       "Version":"2012-10-17",
       "Statement":[
          {
             "Effect":"Allow",
             "Principal":{
                "Service":"eks.amazonaws.com"
             },
             "Action":"sts:AssumeRole"
          }
       ]
    }
    EOF
    }
```


Create a Control Plane Security Group

When you create an Amazon EKS cluster, your cluster control plane creates elastic network interfaces
 in your subnets to enable communication with the worker nodes. You should create a security group that
 is dedicated to your Amazon EKS cluster control plane, so that you can apply inbound and outbound rules
 to govern what traffic is allowed across that connection. When you create the cluster, you specify this security group,
 and that is applied to the elastic network interfaces that are created in your subnets.



 To create a control plane security group

     In the left navigation pane, for Filter by VPC, select your VPC and choose Security Groups, Create Security Group.

     Note

     If you don't see your new VPC here, refresh the page to pick it up.

     Fill in the following fields and choose Yes, Create:

         For Name tag, provide a name for your security group. For example, <cluster-name>-control-plane.

         For Description, provide a description of your security group to help you identify it later.

         For VPC, choose the VPC that you are using for your Amazon EKS cluster.


Download aws authenticator

```sh

```

Validate by running

```sh
heptio-authenticator-aws help
```

Check if you have latest awscli installed, you should get output similar to one below
```sh
aws eks describe-cluster --name test-cluster

{
    "cluster": {
        "status": "ACTIVE",
        "endpoint": "https://1F3D31820046A120545D3A2FC1422C04.sk1.us-east-1.eks.amazonaws.com",
        "name": "test-cluster",
        "certificateAuthority": {
            "data": "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUN5RENDQWJDZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRFNE1EY3dOakUxTlRVME1Gb1hEVEk0TURjd016RTFOVFUwTUZvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBT294CkIyRzB5eU4zeUl6UXlSRS9WdWZDMFg4UVlyeVVlbXV1K3RVNXA4TVozcE5HUDlqZXlQazl2bWFGcENUbWF5VGIKMTRWQnVBUGxhbXI1MGRUa2pqVDE3czhmUDZhb085WVRJeHFuMUJHdmlaK0EvLzlnVkFqaC9iT1pYL2xpcXY1MAppSk53TUl2elZxZ2FmTStJdUpBbWxvd3lOU0xwQk9DRjIrSThkQ3ZXdWZha1BLc3BPUzJRci84YVhIUVJCYmhCCkhIU09IM05wcG9mb3pmc3Zud3VqQXc1bmhiTDlqL1MrMEpDanRLRW1BdGRodzE3cVhDeXVMOHlRTFBSUGxpaGUKc0tvd0VDWk85WDRiYjlPb2Y4REtrcVJ6SkU5UytybzRtSmJkVjdwTjFVdUxPU1ZGYmdzQ25tdGtKK0h1SG4yWgpLNXVhQURsbkdyS0s4TzlQVEI4Q0F3RUFBYU1qTUNFd0RnWURWUjBQQVFIL0JBUURBZ0trTUE4R0ExVWRFd0VCCi93UUZNQU1CQWY4d0RRWUpLb1pJaHZjTkFRRUxCUUFEZ2dFQkFHQnVUMjFpUXQrT1Fodk8yY2d4UjF4QUQraGoKNTJKWVpiQ2VqeEZPQkU5VnIxN1RjQVdheWhtelBiTzUrZjR4dEJhS0wrdTUzbk1UNXlrVnZvUU10eEZtaVk4awovc3F2dk9KeTd4QVE5bmJXVnB2RFd0dE5Tc04wNjNKL2pxVXZrNU03UlNTejMreldFQjErTkVHN2hYb0ZCR2pVClVFeFQ0cWhpalBmTTZwc3ZRZDZOck9lNS9iNUIvZUh0WFFndzkvS3hMZXFmNDhLc1ZWUFlIbU1Eb2hvazVuL1UKV3pRVnAwOUJkeGJFbG9ob2lLTDNRNGJ0S3NpVU45bWJLRCtBZldDNEt0YjlGblZsRG42bG5YK3ArV0hnZ2FsaApaNUE2NWZqZjNUSWdsc0Uvb05idnBHN2JBS3NHQ0JvQ21iS2g0eE5LL2FtWG9hazU3bEpnaDRYVXlCOD0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo="
        },
        "roleArn": "arn:aws:iam::672574731473:role/EKSClusterRole",
        "resourcesVpcConfig": {
            "subnetIds": [
                "subnet-065058abfee2adfca",
                "subnet-0eb04ec6e3f359b5c",
                "subnet-0fd73ea9b4a7dab35",
                "subnet-0ca730350e571154b"
            ],
            "vpcId": "vpc-0daf88b515eac80ab",
            "securityGroupIds": [
                "sg-09de76fce3a132c15"
            ]
        },
        "version": "1.10",
        "arn": "arn:aws:eks:us-east-1:672574731473:cluster/test-cluster",
        "createdAt": 1530892117.396
    }
}


```


# Step 4 EKS cluster

Now it is time to launch the cluster, either via UI 
or using provisioning tool of your choice


Making cluster to ECS might seem a bit tricky , as by default AWS proposes to hold
cluster info in the separate files, like  `~/.kube/eksconfig`  and use environment
variables for switching context `export KUBECONFIG=~/.kube/eksconfig`

If you have multiple clusters configured, that's for sure will not be convenient to you.

```
apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.demo.endpoint}
    certificate-authority-data: ${aws_eks_cluster.demo.certificate_authority.0.data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: heptio-authenticator-aws
      args:
        - "token"
        - "-i"
        - "${var.cluster-name}"
        # - "-r"
        # - "<role-arn>"
      # env:
        # - name: AWS_PROFILE
        #   value: "<aws-profile>"
```

for example above, you could validate, if you configured your cluster and kubectl right.

```
kubectx
aws

kubectl get svc
NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   172.20.0.1   <none>        443/TCP   4d

```


# Step 5,6  Now it is time to launch worker nodes

At a time being AWS recommends to launch stack using, for example, following cloud formation template
https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/amazon-eks-nodegroup.yaml

What you would need from outcomes, is record the NodeInstanceRole for the node group that was created.
You need this when you configure your Amazon EKS worker nodes.

On outputs pane you would see output kind of

```
arn:aws:iam::672574731473:role/test-cluster-worker-nodes-NodeInstanceRole-XF8G1BPXC56B
```

final step would be ensuring that worker nodes can join your cluster.

You would need template for kubernetes configuration map

https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/aws-auth-cm.yaml

```sh
curl -O https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/aws-auth-cm.yaml

cat aws-auth-cm.yaml

apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: <ARN of instance role (not instance profile)>
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes

```

amend role arn and apply changes with

```sh

kubectl apply -f aws-auth-cm.yaml
configmap "aws-auth" created

```

In a few minutes your fleet should be ready

```sh

kubectl get nodes
NAME                          STATUS     ROLES     AGE       VERSION
ip-10-11-1-210.ec2.internal   NotReady   <none>    11s       v1.10.3
ip-10-11-3-36.ec2.internal    NotReady   <none>    14s       v1.10.3
ip-10-11-3-4.ec2.internal     NotReady   <none>    9s        v1.10.3

~~~~~~~~~~~~

kubectl get nodes
NAME                          STATUS    ROLES     AGE       VERSION
ip-10-11-1-210.ec2.internal   Ready     <none>    1m        v1.10.3
ip-10-11-3-36.ec2.internal    Ready     <none>    1m        v1.10.3
ip-10-11-3-4.ec2.internal     Ready     <none>    1m        v1.10.3
```


Troubleshouting ...

Now lets start smth

```
kubectl run -i --tty --image busybox dns-test --restart=Never --rm /bin/sh
```

if you see state pending

```
NAME       READY     STATUS    RESTARTS   AGE
dns-test   0/1       Pending   0          1m

```

you might want immediately check

```sh
kubectl get events
```

you might see smth like

```
LAST SEEN   FIRST SEEN   COUNT     NAME                        KIND      SUBOBJECT   TYPE      REASON             SOURCE              MESSAGE
34s         5m           22        dns-test.15404a7104cc67cf   Pod                   Warning   FailedScheduling   default-scheduler   no nodes available to schedule pods
```

where in message you will get hint about the issue

troubleshouting hints are following:

https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html

