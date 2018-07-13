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

# Getting started with kubernetes cluster on AWS

AWS provides comprehensive guide to start with EKS on a link
https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html

Next steps generally follow that guide, difference is that provisioning
play is (can be) implemented purely with terraform w/o cloud templates.

It has advantage in a way how we do deployments, but in your scenario cloud templates might have advantage too.

## First step is creating a VPC with Public and Private Subnets for Your Amazon EKS Cluster

The simpliest VPC would be all subnets public, like seen on cloud template
( https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/amazon-eks-vpc-sample.yaml )

But if your goal is to reuse that in a production, the reasonable would be VPC with private and public parts, like  https://docs.aws.amazon.com/eks/latest/userguide/create-public-private-vpc.html


At the moment there are limitations:  https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html

Let's proceed with recommended network architecture that uses private subnets for your worker nodes and public subnets for Kubernetes to create internet-facing load balancers within

### Step 1.1: Create an Elastic IP Address for Your NAT Gateway(s)

Worker nodes in private subnets require a NAT gateway for outbound internet access. A NAT gateway requires an Elastic IP address in your public subnet, but the VPC wizard does not create one for you. Create the Elastic IP address before running the VPC wizard.

To create an Elastic IP address

Open the Amazon VPC console at https://console.aws.amazon.com/vpc/.

In the left navigation pane, choose Elastic IPs.
Choose Allocate new address, Allocate, Close.
Note the Allocation ID for your newly created Elastic IP address; you enter this later in the VPC wizard.

```tf

// reserve elastic ip for nat gateway

resource "aws_eip" "nat_eip" {
  vpc = true
  tags {
    Environment = "${local.env}"
  }
}

resource "aws_eip" "nat_eip_2" {
  vpc = true
  tags {
    Environment = "${local.env}"
  }
}

```


### Step 1.2: Run the VPC Wizard

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

//Base VPC Networking
//EKS requires the usage of Virtual Private Cloud to provide the base for its networking configuration.


resource "aws_vpc" "cluster" {
  cidr_block = "${var.vpc_cidr}"
  enable_dns_hostnames = true

  tags = "${merge(
    local.common_tags,
    map(
      "Name", "${local.env}-eks-vpc"
    )
  )}"

}

//The below will create a ${var.public_subnet_cidr} VPC,
//two ${var.public_subnet_cidr} public subnets,
//two ${var.private_subnet_cidr} private subnets with nat instances,
//an internet gateway,
//and setup the subnet routing to route external traffic through the internet gateway:

// public subnets
resource "aws_subnet" "eks-public" {
  vpc_id = "${aws_vpc.cluster.id}"

  cidr_block = "${var.public_subnet_cidr}"
  availability_zone = "${local.availabilityzone}"

  tags = "${merge(
    local.common_tags,
    map(
      "Name", "${local.env}-eks-public"
    )
  )}"

}


resource "aws_subnet" "eks-public-2" {
  vpc_id = "${aws_vpc.cluster.id}"

  cidr_block = "${var.public_subnet_cidr2}"
  availability_zone = "${local.availabilityzone2}"

  tags = "${merge(
    local.common_tags,
    map(
      "Name", "${local.env}-eks-public-2"
    )
  )}"

}


// private subnet
resource "aws_subnet" "eks-private" {
  vpc_id = "${aws_vpc.cluster.id}"

  cidr_block = "${var.private_subnet_cidr}"
  availability_zone = "${local.availabilityzone}"

  tags = "${merge(
    local.common_tags,
    map(
      "Name", "${local.env}-eks-private"
    )
  )}"

}

resource "aws_subnet" "eks-private-2" {
  vpc_id = "${aws_vpc.cluster.id}"

  cidr_block = "${var.private_subnet_cidr2}"
  availability_zone = "${local.availabilityzone2}"

  tags = "${merge(
    local.common_tags,
    map(
      "Name", "${local.env}-eks-private-2"
    )
  )}"

}


// internet gateway, note: creation takes a while

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.cluster.id}"
  tags {
    Environment = "${local.env}"
  }
}



// reserve elastic ip for nat gateway

resource "aws_eip" "nat_eip" {
  vpc = true
  tags {
    Environment = "${local.env}"
  }
}

resource "aws_eip" "nat_eip_2" {
  vpc = true
  tags {
    Environment = "${local.env}"
  }
}


// create nat once internet gateway created
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = "${aws_eip.nat_eip.id}"
  subnet_id = "${aws_subnet.eks-public.id}"
  depends_on = ["aws_internet_gateway.igw"]
  tags {
    Environment = "${local.env}"
  }
}

resource "aws_nat_gateway" "nat_gateway_2" {
  allocation_id = "${aws_eip.nat_eip_2.id}"
  subnet_id = "${aws_subnet.eks-public-2.id}"
  depends_on = ["aws_internet_gateway.igw"]
  tags {
    Environment = "${local.env}"
  }

}


//Create private route table and the route to the internet
//This will allow all traffics from the private subnets to the internet through the NAT Gateway (Network Address Translation)

resource "aws_route_table" "private_route_table" {
  vpc_id = "${aws_vpc.cluster.id}"
  tags {
    Environment = "${local.env}"
    Name = "${local.env}-private-route-table"
  }

}

resource "aws_route_table" "private_route_table_2" {
  vpc_id = "${aws_vpc.cluster.id}"
  tags {
    Environment = "${local.env}"
    Name = "${local.env}-private-route-table-2"
  }

}

resource "aws_route" "private_route" {
  route_table_id  = "${aws_route_table.private_route_table.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = "${aws_nat_gateway.nat_gateway.id}"
}

resource "aws_route" "private_route_2" {
  route_table_id  = "${aws_route_table.private_route_table_2.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = "${aws_nat_gateway.nat_gateway_2.id}"
}


resource "aws_route_table" "eks-public" {
  vpc_id = "${aws_vpc.cluster.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags {
    Environment = "${local.env}"
    Name = "${local.env}-eks-public"
  }

}


resource "aws_route_table" "eks-public-2" {
  vpc_id = "${aws_vpc.cluster.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags {
    Environment = "${local.env}"
    Name = "${local.env}-eks-public-2"
  }
}


// associate route tables

resource "aws_route_table_association" "eks-public" {
  subnet_id = "${aws_subnet.eks-public.id}"
  route_table_id = "${aws_route_table.eks-public.id}"
}

resource "aws_route_table_association" "eks-public-2" {
  subnet_id = "${aws_subnet.eks-public-2.id}"
  route_table_id = "${aws_route_table.eks-public-2.id}"
}


resource "aws_route_table_association" "eks-private" {
  subnet_id = "${aws_subnet.eks-private.id}"
  route_table_id = "${aws_route_table.private_route_table.id}"
}


resource "aws_route_table_association" "eks-private-2" {
  subnet_id = "${aws_subnet.eks-private-2.id}"
  route_table_id = "${aws_route_table.private_route_table_2.id}"
}

```


## Step 2 create your Amazon EKS service role

Open the IAM console at https://console.aws.amazon.com/iam/.

Choose Roles, then Create role.

Choose EKS from the list of services, then Allows Amazon EKS to manage your clusters on your behalf for your use case, then Next: Permissions.

Choose Next: Review.

For Role name, enter a unique name for your role, such as eksServiceRole, then choose Create role.



Terraform definition for the role goes as below.

```tf
//Kubernetes Masters
//This is where the EKS service comes into play.
//It requires a few operator managed resources beforehand so that Kubernetes can properly manage
//other AWS services as well as allow inbound networking communication from your local workstation
//(if desired) and worker nodes.


//EKS Master Cluster IAM Role
//
//IAM role and policy to allow the EKS service to manage or retrieve data from other AWS services.
//For the latest required policy, see the EKS User Guide.


resource "aws_iam_role" "EKSClusterRole" {
  name = "EKSClusterRole-${local.env}",
  description = "Allows EKS to manage clusters on your behalf.",
  assume_role_policy = <<POLICY
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
POLICY
}

//https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html

resource "aws_iam_role_policy_attachment" "eks-policy-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.EKSClusterRole.name}"
}

resource "aws_iam_role_policy_attachment" "eks-policy-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.EKSClusterRole.name}"
}
```


## Step 3: Create a Control Plane Security Group

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

```tf
//EKS Master Cluster Security Group

//This security group controls networking access to the Kubernetes masters.
//Needs to be configured also with an ingress rule to allow traffic from the worker nodes.

resource "aws_security_group" "eks-control-plane-sg" {
  name        = "${local.env}-control-plane"
  description = "Cluster communication with worker nodes [${local.env}]"
  vpc_id      = "${aws_vpc.cluster.id}"

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

# OPTIONAL: Allow inbound traffic from your local workstation external IP
#           to the Kubernetes. You will need to replace A.B.C.D below with
#           your real IP. Services like icanhazip.com can help you find this.
//resource "aws_security_group_rule" "eks-ingress-workstation-https" {
//  cidr_blocks       = ["A.B.C.D/32"]
//  description       = "Allow workstation to communicate with the cluster API Server"
//  from_port         = 443
//  protocol          = "tcp"
//  security_group_id = "${aws_security_group.eks-control-plane-sg.id}"
//  to_port           = 443
//  type              = "ingress"
//}
```


Download aws authenticator, kind of

```sh
install-k8s-heptio-authenticator-aws:
        curl -o ~/dotfiles/docker/heptio-authenticator-aws https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/bin/linux/amd64/heptio-authenticator-aws
        curl -o ~/dotfiles/docker/heptio-authenticator-aws.md5 https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/bin/linux/amd64/heptio-authenticator-aws.md5
        chmod +x ~/dotfiles/docker/heptio-authenticator-aws
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
            "data": "CENSORED"
        },
        "roleArn": "arn:aws:iam::CENSORED:role/EKSClusterRole",
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
        "arn": "arn:aws:eks:us-east-1:CENSORED:cluster/test-cluster",
        "createdAt": 1530892117.396
    }
}


```


## Step 4: create  EKS cluster

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

Terraform part for the creating cluster action would be

```tf

//
//EKS Master Cluster
//This resource is the actual Kubernetes master cluster. It can take a few minutes to provision in AWS.



resource "aws_eks_cluster" "eks-cluster" {
  name     = "${local.cluster_name}"
  role_arn = "${aws_iam_role.EKSClusterRole.arn}"

  vpc_config {
    security_group_ids = ["${aws_security_group.eks-control-plane-sg.id}"]

    subnet_ids = [
      "${aws_subnet.eks-private.id}",
      "${aws_subnet.eks-private-2.id}"
    ]
  }

  depends_on = [
    "aws_iam_role_policy_attachment.eks-policy-AmazonEKSClusterPolicy",
    "aws_iam_role_policy_attachment.eks-policy-AmazonEKSServicePolicy",
  ]
}


locals {
  kubeconfig = <<KUBECONFIG


apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.eks-cluster.endpoint}
    certificate-authority-data: ${aws_eks_cluster.eks-cluster.certificate_authority.0.data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws-${local.env}
current-context: aws-${local.env}
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
        - "${local.cluster_name}"
KUBECONFIG
}

output "kubeconfig" {
  value = "${local.kubeconfig}"
}
```

Note, that instead of patching kubelet config, as per original guide,
you can just get ready-to-use file content from `terraform output kubeconfig`.


## Step 5,6:  Now it is time to launch worker nodes

At a time being AWS recommends to launch stack using, for example, following cloud formation template
https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/amazon-eks-nodegroup.yaml

What you would need from outcomes, is record the NodeInstanceRole for the node group that was created.
You need this when you configure your Amazon EKS worker nodes.

On outputs pane you would see output kind of

```
arn:aws:iam::CENSORED:role/test-cluster-worker-nodes-NodeInstanceRole-XF8G1BPXC56B
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


If you want to omit relying on cloud formation template by URL, and instead stick to fully scripted infrastructure:

### Step 5: on that we prepare worker node and security groups

```tf
//Kubernetes Worker Nodes
//The EKS service does not currently provide managed resources for running worker nodes.
//Here we will create a few operator managed resources so that Kubernetes can properly manage
//other AWS services, networking access, and finally a configuration that allows
//automatic scaling of worker nodes.


//Worker Node IAM Role and Instance Profile
//IAM role and policy to allow the worker nodes to manage or retrieve data from other AWS services.
//It is used by Kubernetes to allow worker nodes to join the cluster.
//
//For the latest required policy, see the EKS User Guide.

resource "aws_iam_role" "EKSNodeRole" {
  name = "eks-${local.cluster_name}-node-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks-node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.EKSNodeRole.name}"
}

resource "aws_iam_role_policy_attachment" "eks-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.EKSNodeRole.name}"
}

resource "aws_iam_role_policy_attachment" "eks-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.EKSNodeRole.name}"
}

resource "aws_iam_instance_profile" "eks-node-instance-profile" {
  name = "terraform-eks-demo"
  role = "${aws_iam_role.EKSNodeRole.name}"
}


//Worker Node Security Group
//This security group controls networking access to the Kubernetes worker nodes.


resource "aws_security_group" "eks-nodes-sg" {
  name  =  "${local.cluster_name}-nodes-sg"
  description = "Security group for all nodes in the cluster [${local.env}] "
  vpc_id = "${aws_vpc.cluster.id}"
  //    ingress {
  //      from_port       = 0
  //      to_port         = 0
  //      protocol        = "-1"
  //      description = "allow nodes to communicate with each other"
  //      self = true
  //    }

  //    ingress {
  //      from_port       = 1025
  //      to_port         = 65535
  //      protocol        = "tcp"
  //      description = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  //      security_groups = ["${aws_security_group.eks-control-plane.id}"]
  //    }


  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = "${
    map(
     "Name", "${local.cluster_name}-nodes-sg",
     "kubernetes.io/cluster/${local.cluster_name}", "owned",
    )
  }"
}


//Worker Node Access to EKS Master Cluster
//Now that we have a way to know where traffic from the worker nodes is coming from,
//we can allow the worker nodes networking access to the EKS master cluster.

resource "aws_security_group_rule" "https_nodes_to_plane" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.eks-control-plane-sg.id}"
  source_security_group_id = "${aws_security_group.eks-nodes-sg.id}"
  depends_on = ["aws_security_group.eks-nodes-sg", "aws_security_group.eks-control-plane-sg" ]
}


resource "aws_security_group_rule" "communication_plane_to_nodes" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65534
  protocol                 = "tcp"
  security_group_id = "${aws_security_group.eks-nodes-sg.id}"
  source_security_group_id        = "${aws_security_group.eks-control-plane-sg.id}"
  depends_on = ["aws_security_group.eks-nodes-sg", "aws_security_group.eks-control-plane-sg" ]
}

resource "aws_security_group_rule" "nodes_internode_communications" {
  type = "ingress"
  from_port       = 0
  to_port         = 0
  protocol        = "-1"
  description = "allow nodes to communicate with each other"
  security_group_id = "${aws_security_group.eks-nodes-sg.id}"
  self = true
}

```

### Step 5: on that step we are creating autoscaling group


```tf
//Worker Node AutoScaling Group
//Now we have everything in place to create and manage EC2 instances that will serve as our worker nodes
//in the Kubernetes cluster. This setup utilizes an EC2 AutoScaling Group (ASG) rather than manually working with
//EC2 instances. This offers flexibility to scale up and down the worker nodes on demand when used in conjunction
//with AutoScaling policies (not implemented here).
//
//First, let us create a data source to fetch the latest Amazon Machine Image (AMI) that Amazon provides with an
//EKS compatible Kubernetes baked in.

data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["eks-worker-*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon Account ID
}

# EKS currently documents this required userdata for EKS worker nodes to
# properly configure Kubernetes applications on the EC2 instance.
# We utilize a Terraform local here to simplify Base64 encoding this
# information into the AutoScaling Launch Configuration.
# More information: https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/amazon-eks-nodegroup.yaml
locals {
  eks-node-userdata = <<USERDATA
#!/bin/bash -xe

CA_CERTIFICATE_DIRECTORY=/etc/kubernetes/pki
CA_CERTIFICATE_FILE_PATH=$CA_CERTIFICATE_DIRECTORY/ca.crt
mkdir -p $CA_CERTIFICATE_DIRECTORY
echo "${aws_eks_cluster.eks-cluster.certificate_authority.0.data}" | base64 -d >  $CA_CERTIFICATE_FILE_PATH
INTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
sed -i s,MASTER_ENDPOINT,${aws_eks_cluster.eks-cluster.endpoint},g /var/lib/kubelet/kubeconfig
sed -i s,CLUSTER_NAME,${local.cluster_name},g /var/lib/kubelet/kubeconfig
sed -i s,REGION,${var.AWS_REGION},g /etc/systemd/system/kubelet.service
sed -i s,MAX_PODS,20,g /etc/systemd/system/kubelet.service
sed -i s,MASTER_ENDPOINT,${aws_eks_cluster.eks-cluster.endpoint},g /etc/systemd/system/kubelet.service
sed -i s,INTERNAL_IP,$INTERNAL_IP,g /etc/systemd/system/kubelet.service
DNS_CLUSTER_IP=10.100.0.10
if [[ $INTERNAL_IP == 10.* ]] ; then DNS_CLUSTER_IP=172.20.0.10; fi
sed -i s,DNS_CLUSTER_IP,$DNS_CLUSTER_IP,g /etc/systemd/system/kubelet.service
sed -i s,CERTIFICATE_AUTHORITY_FILE,$CA_CERTIFICATE_FILE_PATH,g /var/lib/kubelet/kubeconfig
sed -i s,CLIENT_CA_FILE,$CA_CERTIFICATE_FILE_PATH,g  /etc/systemd/system/kubelet.service
systemctl daemon-reload
systemctl restart kubelet
USERDATA
}

resource "aws_launch_configuration" "eks-launch-configuration" {
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.eks-node-instance-profile.name}"
  image_id                    = "${data.aws_ami.eks-worker.id}"
  instance_type               = "t2.small"
  name_prefix                 = "eks-${local.cluster_name}"
  security_groups             = ["${aws_security_group.eks-nodes-sg.id}"]
  user_data_base64            = "${base64encode(local.eks-node-userdata)}"
  key_name                    = "${var.ec2_keyname}"

  lifecycle {
    create_before_destroy = true
  }
}


//Finally, we create an AutoScaling Group that actually launches EC2 instances based on the
//AutoScaling Launch Configuration.

//NOTE: The usage of the specific kubernetes.io/cluster/* resource tag below is required for EKS
//and Kubernetes to discover and manage compute resources.

resource "aws_autoscaling_group" "eks-autoscaling-group" {
  desired_capacity     = 2
  launch_configuration = "${aws_launch_configuration.eks-launch-configuration.id}"
  max_size             = 2
  min_size             = 1
  name                 = "eks-${local.cluster_name}"
  vpc_zone_identifier  = ["${aws_subnet.eks-private.id}", "${aws_subnet.eks-private-2.id}"]


  tag {
    key                 = "Environment"
    value               = "${local.env}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "eks-${local.cluster_name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${local.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }
}

//NOTE: At this point, your Kubernetes cluster will have running masters and worker nodes, however, the worker nodes will
//not be able to join the Kubernetes cluster quite yet. The next section has the required Kubernetes configuration to
//enable the worker nodes to join the cluster.


//Required Kubernetes Configuration to Join Worker Nodes
//The EKS service does not provide a cluster-level API parameter or resource to automatically configure the underlying
//Kubernetes cluster to allow worker nodes to join the cluster via AWS IAM role authentication.


//To output an IAM Role authentication ConfigMap from your Terraform configuration:

locals {
  config-map-aws-auth = <<CONFIGMAPAWSAUTH


apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.EKSNodeRole.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
CONFIGMAPAWSAUTH
}

output "config-map-aws-auth" {
  value = "${local.config-map-aws-auth}"
}


//Run
//
//terraform output config-map-aws-auth and save the configuration into a file,
//e.g. config-map-aws-auth.yaml
//
//Run kubectl apply -f config-map-aws-auth.yaml
//
//You can verify the worker nodes are joining the cluster via: kubectl get nodes --watch
//At this point, you should be able to utilize Kubernetes as expected!
//

```

On that step, you should also have fully working EKS cluster.
Upon `terraform apply` run you should see smth like

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

## Questions?


### Troubleshouting ...

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

Troubleshouting hints from AWS can be found on

https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html
