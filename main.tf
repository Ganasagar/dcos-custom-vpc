///////////////// VARIABLES-DEFINATION /////////////////
//
// Root Module that calls all the relavant modules for DC/OS installation in AWS
//
////////////////////////////////////////////
provider "aws" {
  region = "${var.region}"
}
// create a ssh-key-pair.
resource "aws_key_pair" "deployer" {
  provider = "aws"
  key_name   = "${var.cluster_name}-deployer-key"
#  public_key = "${coalesce(var.ssh_public_key, file("~/.ssh/id_rsa.pub"))}"
  public_key = "${var.ssh_public_key}"
}
// select our default VPC.
// instead of default you could specify an name or ID.
// https://www.terraform.io/docs/providers/aws/d/vpc.html
data "aws_vpc" "default" {
  provider = "aws"
  id = "${var.vpc_id}"
}
// we want to use all the subnets in this VPC
// You could use tags if you only want a subset of subnets
// https://www.terraform.io/docs/providers/aws/d/subnet_ids.html
// For redundancy make sure your subnets are distributed
// across availability zones
data "aws_subnet_ids" "default_subnets" {
  provider = "aws"
  vpc_id   = "${data.aws_vpc.default.id}"
  filter {
    name   = "tag:type"  # insert values of your tag's name ex-  tag:<YOUR_TAG_NAME>
    values = ["dcos-custom-subnet-filter"] # insert values of your tag
  }
}
// we use intermediate local variables. So whenever it is needed to replace
// or drop a modules it is easier to change just the local variable instead
// of all other references
locals {
  key_name     = "${aws_key_pair.deployer.key_name}"
  vpc_id       = "${data.aws_vpc.default.id}"
  subnet_range = "${data.aws_vpc.default.cidr_block}"
  subnet_ids   = ["${data.aws_subnet_ids.default_subnets.ids}"]
}
  
data "null_data_source" "lb_rules" {
  count = "${length(var.public_agents_additional_ports)}"

  inputs = {
    port     = "${element(var.public_agents_additional_ports, count.index)}"
    protocol = "tcp"
  }
}
// Firewall. Create policies for instances and load balancers.
// https://registry.terraform.io/modules/dcos-terraform/security-groups/aws
// Firewall. Create policies for instances and load balancers
module "dcos-security-groups" {
  source  = "dcos-terraform/security-groups/aws"
  version = "~> 0.2.0"

  providers = {
    aws = "aws"
  }

  vpc_id                         = "${local.vpc_id}"
  subnet_range                   = "${local.subnet_range}"
  cluster_name                   = "${var.cluster_name}"
  admin_ips                      = ["${var.admin_ips}"]
  public_agents_additional_ports = ["${var.public_agents_additional_ports}"]
}
// we use intermediate local variables. So whenever it is needed to replace
// or drop a modules it is easier to change just the local variable instead
// of all other references
locals {
  instance_security_groups             = ["${list(module.dcos-security-groups.internal, module.dcos-security-groups.admin)}"]
  public_security_groups               = ["${list(module.dcos-security-groups.internal, module.dcos-security-groups.admin, module.dcos-security-groups.public_agents)}"]
  security_groups_elb_masters          = ["${list(module.dcos-security-groups.admin,module.dcos-security-groups.internal)}"]
  security_groups_elb_masters_internal = ["${list(module.dcos-security-groups.internal)}"]
  security_groups_elb_public_agents    = ["${list(module.dcos-security-groups.admin,module.dcos-security-groups.internal)}"]
}

// DISABLING this IAM section, since wabtec will require passing in their own pre-existing IAM profile
// Permissions creates instances profiles so you could use Rexray and Kubernetes with AWS support
// These set of IAM Rules will be applied as Instance Profiles. They will enable Rexray to maintain
// volumes in your cluster
// https://registry.terraform.io/modules/dcos-terraform/iam/aws
//module "dcos-iam" {
//  source  = "dcos-terraform/iam/aws"
//  version = "~> 0.2.0"
//  providers = {
//    aws = "aws"
//  }
//  cluster_name = "${var.cluster_name}"
//}

// This spawning the Bootstrap node which will be used as the internal source for the installer.
// https://registry.terraform.io/modules/dcos-terraform/bootstrap/aws
module "dcos-bootstrap-instance" {
  source  = "dcos-terraform/bootstrap/aws"
  version = "~> 0.2.0"
  providers = {
    aws = "aws"
  }
  cluster_name = "${var.cluster_name}"
  aws_subnet_ids         = ["${local.subnet_ids}"]
  aws_security_group_ids = ["${local.instance_security_groups}"]
  aws_key_name           = "${local.key_name}"
  aws_instance_type      = "${var.bootstrap_instance_type}"
  aws_associate_public_ip_address = "${var.aws_associate_public_ip_address}"
  tags = "${var.tags}"
}
// This module creates the master instances of your DC/OS cluster. If neccessary you can change the instance type or OS.
// https://registry.terraform.io/modules/dcos-terraform/masters/aws
module "dcos-master-instances" {
  source  = "dcos-terraform/masters/aws"
  version = "~> 0.2.0"
  providers = {
    aws = "aws"
  }
  cluster_name = "${var.cluster_name}"
  aws_subnet_ids         = ["${local.subnet_ids}"]
  aws_security_group_ids = ["${local.instance_security_groups}"]
  aws_key_name           = "${local.key_name}"
  aws_instance_type      = "${var.masters_instance_type}"
  aws_iam_instance_profile = "${local.masters_iam_instance_profile}"
  num_masters = "${var.num_masters}"
  aws_associate_public_ip_address = "${var.aws_associate_public_ip_address}"
  tags = "${var.tags}"
}
// This module create the private agent instances of your DC/OS cluster. If neccessary you can change the instance type or OS.
// https://registry.terraform.io/modules/dcos-terraform/private-agents/aws
module "dcos-privateagent-instances" {
  source  = "dcos-terraform/private-agents/aws"
  version = "~> 0.2.0"
  providers = {
    aws = "aws"
  }
  cluster_name = "${var.cluster_name}"
  aws_subnet_ids         = ["${local.subnet_ids}"]
  aws_security_group_ids = ["${local.instance_security_groups}"]
  aws_key_name           = "${local.key_name}"
  aws_instance_type      = "${var.private_agents_instance_type}"
  aws_root_volume_type = "gp2"
  aws_root_volume_size = "${var.private_agents_root_volume_size}"
  aws_iam_instance_profile = "${local.private_agents_iam_instance_profile}"
  num_private_agents = "${var.num_private_agents}"
  aws_associate_public_ip_address = "${var.aws_associate_public_ip_address}"
  tags = "${var.tags}"
}
// This module create the public agent instances of your DC/OS cluster. If neccessary you can change the instance type or OS.
// https://registry.terraform.io/modules/dcos-terraform/public-agents/aws
module "dcos-publicagent-instances" {
  source  = "dcos-terraform/public-agents/aws"
  version = "~> 0.2.0"
  providers = {
    aws = "aws"
  }
  cluster_name = "${var.cluster_name}"
  aws_subnet_ids         = ["${local.subnet_ids}"]
  aws_security_group_ids = ["${local.public_security_groups}"]
  aws_key_name           = "${local.key_name}"
  aws_instance_type      =  "${var.public_agents_instance_type}"
  aws_root_volume_type   = "gp2"
  aws_iam_instance_profile = "${local.public_agents_iam_instance_profile}"
  num_public_agents = "${var.num_public_agents}"
  aws_associate_public_ip_address = "${var.aws_associate_public_ip_address}"
  tags = "${var.tags}"
}
// we use intermediate local variables. So whenever it is needed to replace
// or drop a modules it is easier to change just the local variable instead
// of all other references
locals {
  bootstrap_ip         = "${module.dcos-bootstrap-instance.public_ip}"
  bootstrap_private_ip = "${module.dcos-bootstrap-instance.private_ip}"
  bootstrap_os_user    = "${var.os_user}"
  master_ips         = ["${module.dcos-master-instances.public_ips}"]
  master_private_ips = ["${module.dcos-master-instances.private_ips}"]
  masters_os_user    = "${var.os_user}"
  master_instances   = ["${module.dcos-master-instances.instances}"]
  private_agent_ips         = ["${module.dcos-privateagent-instances.public_ips}"]
  private_agent_private_ips = ["${module.dcos-privateagent-instances.private_ips}"]
  private_agents_os_user    = "${var.os_user}"
  public_agent_ips         = ["${module.dcos-publicagent-instances.public_ips}"]
  public_agent_private_ips = ["${module.dcos-publicagent-instances.private_ips}"]
  public_agents_os_user    = "${var.os_user}"
  public_agent_instances   = ["${module.dcos-publicagent-instances.instances}"]
  masters_iam_instance_profile = "${var.masters_iam_instance_profile}"
  private_agents_iam_instance_profile = "${var.private_agents_iam_instance_profile}"
  public_agents_iam_instance_profile = "${var.public_agents_iam_instance_profile}"
  masters_acm_cert_arn = "${var.masters_acm_cert_arn}"
  masters_internal_acm_cert_arn = "${var.masters_internal_acm_cert_arn}"
  public_agents_acm_cert_arn = "${var.public_agents_acm_cert_arn}"

}
// Load balancers is providing three load balancers.
// - public master load balancer
//   this load balancer is meant to be used as your main access to the cluster and will lead you to the DC/OS Frontend.
//   you can specify masters_acm_cert_arn to use an ACM certificate for proper SSL termination.
//   https://registry.terraform.io/modules/dcos-terraform/elb-dcos/aws
// - internal master load balancer
//   this load balancer can be used for accessing the master internally in the cluster.
//   https://registry.terraform.io/modules/dcos-terraform/elb-dcos/aws
// - public agents load balancer
//   This load balancer is meant to be the main public access point into your application. If you use marathon-lb or edge-lb
//   it will make sure your custermers will allways be able to access one of the public agents even if one failed.
//   you can specify masters_acm_cert_arn to use an ACM certificate for proper SSL termination.
//   https://registry.terraform.io/modules/dcos-terraform/elb-dcos/aws
module "dcos-lb" {
  source  = "dcos-terraform/lb-dcos/aws"
  version = "~> 0.2.0"

  providers = {
    aws = "aws"
  }

  internal                           = true
  cluster_name                       = "${var.cluster_name}"
  subnet_ids                         = ["${data.aws_subnet_ids.default_subnets.ids}"]
  security_groups_masters            = ["${list(module.dcos-security-groups.admin,module.dcos-security-groups.internal)}"]
  security_groups_masters_internal   = ["${list(module.dcos-security-groups.internal)}"]
  security_groups_public_agents      = ["${list(module.dcos-security-groups.internal, module.dcos-security-groups.admin)}"]
  masters_acm_cert_arn               = "${local.masters_acm_cert_arn}"
  masters_internal_acm_cert_arn      = "${local.masters_internal_acm_cert_arn}"
  public_agents_acm_cert_arn         = "${local.public_agents_acm_cert_arn}"
  master_instances                   = ["${module.dcos-master-instances.instances}"]
  num_masters                        = "${var.num_masters}"
  num_public_agents                  = "${var.num_public_agents}"
  public_agent_instances             = ["${module.dcos-publicagent-instances.instances}"]
  public_agents_additional_listeners = ["${data.null_data_source.lb_rules.*.outputs}"]
  tags                               = "${var.tags}"
}
// we use intermediate local variables. So whenever it is needed to replace
// or drop a modules it is easier to change just the local variable instead
// of all other references
locals {
  masters_dns_name = "${module.dcos-lb.masters_dns_name}"
}
// DC/OS Install module takes a list of public and private ip addresses of each of the node type to install.
// - <node type>_ip - This is the "public" address of the given node type. Public in this case mean the address is reachable from the system running terraform. Public and private address could be the same.
// - <node type>_private_ip - These are the addresses the cluster could reach its nodes internally.
// - <node type>_os_user - specifies the user used for sshing into the nodes.
// https://registry.terraform.io/modules/dcos-terraform/dcos-install-remote-exec/null
// DC/OS Options. Install takes also all the options for runnign Genconfig. Whatever you want to change at the DC/OS config needs to be
// specified in this module. A good description could be found here: https://registry.terraform.io/modules/dcos-terraform/dcos-core/template
module "dcos-install" {
  source  = "dcos-terraform/dcos-install-remote-exec/null"
  version = "~> 0.2.0"
  # bootstrap
  bootstrap_ip         = "${coalesce(local.bootstrap_ip,local.bootstrap_private_ip)}"
  bootstrap_private_ip = "${local.bootstrap_private_ip}"
  bootstrap_os_user    = "${local.bootstrap_os_user}"
  # master
  master_ips         = ["${local.master_ips}"]
  master_private_ips = ["${local.master_private_ips}"]
  masters_os_user    = "${local.masters_os_user}"
  num_masters        = "${var.num_masters}"
  # private agent
  private_agent_ips         = ["${local.private_agent_ips}"]
  private_agent_private_ips = ["${local.private_agent_private_ips}"]
  private_agents_os_user    = "${local.private_agents_os_user}"
  num_private_agents        = "${var.num_private_agents}"
  # public agent
  public_agent_ips         = ["${local.public_agent_ips}"]
  public_agent_private_ips = ["${local.public_agent_private_ips}"]
  public_agents_os_user    = "${local.public_agents_os_user}"
  num_public_agents        = "${var.num_public_agents}"
  # DC/OS options
  dcos_cluster_name = "${var.cluster_name}"
  dcos_version      = "${var.dcos_version}"
  # use AWS local resolvers instead of google
  dcos_resolvers = ["169.254.169.253"]
  dcos_variant                   = "${var.dcos_type}"
  dcos_license_key_contents      = "${var.dcos_license_key_contents}"
  dcos_master_discovery          = "static"
  dcos_exhibitor_storage_backend = "static"
}
output "masters_dns_name" {
  description = "This is the load balancer address to access the DC/OS UI"
  value       = "${local.masters_dns_name}"
}
////////////////////////////////////////////
/////////////// END OF MODULES //////////////
////////////////////////////////////////////




