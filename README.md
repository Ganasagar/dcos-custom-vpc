# Customized Universal Installer 
This repository walks through the steps for installing a DC/OS cluter using universal installer in a environment where you cannot create a VPC. the default installation of DC/OS using universal installer works under the pretense that it would be able to create VPC's and everything within a VPC before actual DC/OS installation is initiated. This also means that a VPC is dedicated only for DC/OS installation. Often we run into team's that do not have privileges to create VPC and will need to work with existing VPC's & Subnets at minimum. This means that instead of installer randomly picking subnets we would need to control which sunets they fall under as well. This repo also assume that you are faimiliar with standard AWS terminology 

## Prerequisites

WorkStation Pre-reqs
- Linux, macOS, or windows
- Command-line shell terminal such as Bash or PowerShell
- Verified Amazon Web Services (AWS) account and AWS IAM user profile with permissions
- Follow instructions from here https://docs.d2iq.com/mesosphere/dcos/2.0/installing/evaluation/aws/

#### VPC-Prereqs
Universal installer is designed to build an entire VPC to deploy install DC/OS. However since that approch would not suit adaption every customers meeds we would need to alter
the universal installer's deployment. This repo gives you the privilieges to define existing VPC and Subnets rather than letting the Universal installer create them 
on the go. However it's important you have configured that VPC you would like to deploy DC/OS prior to starting with the installation procedure.

- Pick the VPC to deploy DC/OS in, Have the VPC id ready to be plugged in during installation  
- Ensure an Internet Gateway attached to the VPC to be able to talk to the internet.
- This custom installer REQUIRES all DC/OS nodes to have connectivity to the internet and all traffic should be allowed between the nodes.
- At least 2 or more Subnets which span over more than 1 Availability Zones's (1 subnet per AZ)
    - If deploying in public subnets ensure you have a route to the Internet Gateway, Check to see if you able to install packages from internet
    - If deploying in private subnets ensure that you have route configured NAT-Gateway or NAT-Instance, Check to see if you able to install packages from internet
- Ensure that there are no ACL's defined that would restrict traffic flow between the ec2's that would come up in the subnets 
- Ensure that there are no ACL's defined that would restrict traffic flow between the ec2's and NAT-Gateway or NAT-Instances for egress traffic.
- Ensure you tag your desired subnets with relavant tag in place for subnets using which they would be picked e.g. type:dcos-custom-subnet-filter.
    - Note: This is tag using which Universal Installer would you pick the subnets to install DC/OS in.    
- The IAM user should have privilieges to create infrastrucure within VPC. 



## Installation

1. Add all of you parameters in `terraform.tfvars` file in this repo and save the file. look at the comments for details 

2. By default, terraform will expect VPC subnets to be tagged with type:dcos-custom-subnet-filter. This will determines where your ec2 instances and load balancers will be built. Be sure that your subnets are tagged accordingly before deploying. If you prefer to tag subnets with somehting different, you can add your preferred subnet tags in `main.tf` under the aws_subnet_ids section between line 28-35. 

4. Load the private ssh key to the ssh-agent. This will allow bootstrap server to run ansible ssh sessions against all the nodes. 
```bash
eval "$(ssh-agent -s)" && ssh-add <path-to-your-private-key-for-the-public-key-used-in-variables.tf>
```

Example:
```bash
eval "$(ssh-agent -s)" && ssh-add /home/admin/.ssh/admin-private-key.pem
```

5. Verify that ssh key is added to agent.
```bash
ssh-add -L 
```

6. Authenticate to your target AWS account using your preferred method. (Access keys, Okta, etc)

5. Validate that all your files are syntax error free, If there are errors they would pop up if not it would return the cursor.
```bash
terraform validate  
```

6. Generate terraform plan
```bash
terraform plan -out=plan.out
```

7. Apply the terraforn plan to build the cluster 
```bash 
terraform apply "plan.out"
```

Notes/Gotcha's 

1. Before you begin make sure, you IAM user has right privileges, for a check try to run a few AWS commands to validate if the IAM user has the right access

2. Ensure you keep loading keys before you run terrafrom apply, without keys loaded to the ssh-agent installer wont be able to access the ec2 instances

3. Always vaildate the files after making changes to ensure you are not running build on files with errrors 

3. In case of errors make a judgement call on wether to destroy the cluster or re-apply configurations each has its perks and downsides 

4. Make sure you can access internet using the NAT-instances,

5. The AMI in-use seems to have issues with NIC card on the server when using offical CENTOS images 7.4 & 7.6. 7.7 does not exist yet.

6. It might be a better idea to bake your own custom AMI that has been configured for the installation 

7. If you are copying an existing terraform working directory to setup a new environment, be sure to remove the state files so as not to accidentally alter existing infrastructure. Recommend to do the following if copying to a new working directory:
```bash
rm -rf terraform.tfstate*
rm -rf .terraform
rm -rf plan.out
```
