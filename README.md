# Terraform EKS Cluster with Argo CD

This repository contains Terraform configurations to set up an Amazon EKS (Elastic Kubernetes Service) cluster along with Argo CD for GitOps continuous delivery and a kube-prometheus-stack for monitoring.

## Architecture

- **VPC** with public and private subnets across multiple availability zones
- **NAT Gateway** for private subnet internet egress
- **EKS cluster** (v1.32) with managed node groups deployed on private subnets
- **EKS managed add-ons**: vpc-cni, coredns, kube-proxy
- **Argo CD** deployed via Helm for GitOps workflows
- **kube-prometheus-stack** (Prometheus + Grafana + Alertmanager) deployed via Helm for observability

## Repository Structure

```bash
.
├── main.tf # Root module - wires all child modules together
├── modules                  
│   ├── argo-cd # Argo CD Helm release 
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── eks # EKS cluster, node group, IAM roles, SG, add-ons
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── network # VPC, subnets, IGW, NAT Gateway, route tables
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   └── prometheus  #kube-prometheus-stack Helm release
│       ├── main.tf
│       ├── outputs.tf
│       └── variables.tf
├── outputs.tf  # Root outputs
├── providers.tf  # AWS, Helm, and Kubernetes provider configurations
├── README.md
├── terraform.tfvars.example # Example variable values
├── variables.tf # Root input variables
└── versions.tf # Terraform and provider version constraints
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.10.0
- AWS credentials configured (`aws configure` or environment variables)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- [Helm](https://helm.sh/docs/intro/install/) 3+ installed

## Component Versions

| Component | Version |
|---|---|
| Terraform | >= 1.10.0 |
| AWS Provider | ~> 6.0 |
| Helm Provider | ~> 3.0 |
| Kubernetes Provider | ~> 3.0 |
| EKS Kubernetes | 1.32 (standard support) |
| Argo CD Helm Chart | 9.4.1 (App v3.3.0) |
| kube-prometheus-stack Chart | 81.5.0 (Operator v0.88.1) |

## Usage

1. Clone the repository:

    ```sh
    git clone https://github.com/fearfactor3/argocd-eks-terraform
    cd argocd-eks-terraform
    ```

2. Create your `terraform.tfvars` from the example:

    ```sh
    cp terraform.tfvars.example terraform.tfvars
    # Edit terraform.tfvars with your desired values
    ```

3. Initialize Terraform:

    ```sh
    terraform init
    ```

4. Review the Terraform plan:

    ```sh
    terraform plan
    ```

5. Apply the Terraform plan:

    ```sh
    terraform apply
    ```

6. Connect to the cluster:

    ```sh
    aws eks update-kubeconfig --region <your-region> --name <cluster-name>
    ```

7. Retrieve the Argo CD admin password:

    ```sh
    kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath="{.data.password}" | base64 -d
    ```

## Input Variables

| Variable | Description | Type | Default |
|---|---|---|---|
| `aws_region` | AWS region for all resources | `string` | `us-east-1` |
| `project_name` | Project name used for resource naming | `string` | `argocd` |
| `cluster_name` | Name of the EKS cluster | `string` | `argocd-cluster` |
| `cluster_version` | Kubernetes version for the EKS cluster | `string` | `1.32` |
| `environment` | Environment name (Dev, Staging, Prod) | `string` | `Dev` |
| `vpc_cidr` | CIDR block for the VPC | `string` | `10.0.0.0/16` |
| `public_subnets` | CIDR blocks for public subnets | `list(string)` | `["10.0.1.0/24", "10.0.2.0/24"]` |
| `private_subnets` | CIDR blocks for private subnets | `list(string)` | `["10.0.3.0/24", "10.0.4.0/24"]` |
| `azs` | Availability zones | `list(string)` | `["us-east-1a", "us-east-1b"]` |
| `node_group_desired_capacity` | Desired number of worker nodes | `number` | `2` |
| `node_group_max_capacity` | Maximum number of worker nodes | `number` | `3` |
| `node_group_min_capacity` | Minimum number of worker nodes | `number` | `1` |
| `node_group_instance_types` | Instance types for the node group | `list(string)` | `["t3.medium"]` |
| `argocd_chart_version` | Argo CD Helm chart version | `string` | `9.4.1` |
| `prometheus_chart_version` | kube-prometheus-stack Helm chart version | `string` | `81.5.0` |

## Modules

### Network

Sets up the VPC, public and private subnets, internet gateway, NAT gateway with Elastic IP, and route tables for both public and private subnets.

| Variable | Description | Type |
|---|---|---|
| `vpc_cidr` | CIDR block for the VPC | `string` |
| `public_subnets` | List of CIDR blocks for public subnets | `list(string)` |
| `private_subnets` | List of CIDR blocks for private subnets | `list(string)` |
| `azs` | List of availability zones | `list(string)` |
| `project_name` | Name of the project | `string` |

### EKS

Creates the EKS cluster with managed node groups on private subnets, IAM roles and policies, a cluster security group, private endpoint access, and managed add-ons (vpc-cni, coredns, kube-proxy).

| Variable | Description | Type |
|---|---|---|
| `cluster_name` | Name of the EKS cluster | `string` |
| `cluster_version` | Kubernetes version (default: `1.32`) | `string` |
| `vpc_id` | VPC ID for the cluster | `string` |
| `subnet_ids` | Subnet IDs for the cluster (private subnets) | `list(string)` |
| `node_group_desired_capacity` | Desired number of nodes | `number` |
| `node_group_max_capacity` | Maximum number of nodes | `number` |
| `node_group_min_capacity` | Minimum number of nodes | `number` |
| `node_group_instance_types` | Instance types for the node group | `list(string)` |
| `tags` | Tags to apply to AWS resources | `map(string)` |

### Argo CD

Deploys Argo CD via Helm. Custom values are passed as a list of YAML-encoded strings using the Helm provider v3 `values` attribute.

| Variable | Description | Type |
|---|---|---|
| `release_name` | Name of the Helm release | `string` |
| `namespace` | Namespace to install into | `string` |
| `create_namespace` | Whether to create the namespace | `bool` |
| `helm_repo_url` | Helm repository URL | `string` |
| `chart_name` | Helm chart name | `string` |
| `chart_version` | Helm chart version (default: `9.4.1`) | `string` |
| `values` | List of YAML strings to override chart defaults | `list(string)` |

### Prometheus

Deploys the kube-prometheus-stack (Prometheus, Grafana, Alertmanager) via Helm.

| Variable | Description | Type |
|---|---|---|
| `release_name` | Name of the Helm release | `string` |
| `namespace` | Namespace to install into | `string` |
| `create_namespace` | Whether to create the namespace | `bool` |
| `timeout` | Helm install timeout in seconds (default: `2000`) | `number` |
| `helm_repo_url` | Helm repository URL | `string` |
| `chart_name` | Helm chart name | `string` |
| `chart_version` | Helm chart version (default: `81.5.0`) | `string` |
| `values` | List of YAML strings to override chart defaults | `list(string)` |

## Outputs

| Output | Description |
|---|---|
| `eks_cluster_name` | Name of the EKS cluster |
| `eks_cluster_version` | Kubernetes version of the EKS cluster |
| `argocd_release_namespace` | Namespace of the Argo CD Helm release |
| `eks_connect` | `aws eks update-kubeconfig` command for the cluster |
| `argocd_initial_admin_secret` | Command to retrieve the Argo CD initial admin password |
| `argocd_server_load_balancer` | Load balancer hostname for the Argo CD server |

## Cleanup

To destroy all resources:

```sh
terraform destroy
```
