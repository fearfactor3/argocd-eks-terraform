# Terraform EKS Cluster with Argo CD

This repository contains Terraform configurations to set up an Amazon EKS (Elastic Kubernetes Service) cluster along with Argo CD for continuous delivery.

## Repository Structure

```bash
.
├── README.md
├── main.tf
├── modules
│   ├── argo-cd
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── variables.tf
│   │   └── versions.tf
│   ├── eks
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── variables.tf
│   │   └── versions.tf
│   ├── network
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── variables.tf
│   │   └── versions.tf
│   └── prometheus
│       ├── main.tf
│       ├── outputs.tf
│       ├── variables.tf
│       └── versions.tf
├── outputs.tf
├── providers.tf
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) installed
- AWS credentials configured

## Usage

1. Clone the repository:

    ```sh
    git clone https://github.com/fearfactor3/argocd-eks-terraform
    cd argocd-eks-terraform
    ```

2. Initialize Terraform:

    ```sh
    terraform init
    ```

3. Review the Terraform plan:

    ```sh
    terraform plan
    ```

4. Apply the Terraform plan:

    ```sh
    terraform apply
    ```

## Modules

### Network Module

The network module sets up the VPC, subnets, and related networking resources.

- **Source:** `./modules/network`
- **Variables:**
  - `vpc_cidr`: CIDR block for the VPC
  - `public_subnets`: List of CIDR blocks for the public subnets
  - `private_subnets`: LIst of CIDR blocks for the private subnets
  - `azs`: List of availability zones
  - `project_name`: Name of the project

### EKS Module

The EKS module sets up the EKS cluster and node groups.

- **Source:** `./modules/eks`
- **Variables:**
  - `aws_region`: AWS region for the EKS cluster
  - `cluster_name`: Name of the EKS cluster
  - `cluster_version`: Kubernetes version for the EKS cluster
  - `vpc_id`: VPC ID for the EKS cluster
  - `subnet_ids`: Subnets for the EKS cluster
  - `node_group_desired_capacity`: Desired number of nodes in the node group
  - `node_group_max_capacity`: Maximum number of nodes in the node group
  - `node_group_min_capacity`: Minimum number of nodes in the node group
  - `node_group_instance_types`: Instance types for the node group
  - `tags`: Tags to apply to AWS resources

### Argo CD Module

The Argo CD module sets up Argo CD using Helm.

- **Source:** `./modules/argo-cd`
- **Variables:**
  - `release_name`: Name of the Helm release for Argo CD
  - `namespace`: Namespace to install Argo CD into
  - `create_namespace`: Whether to create the namespace if it doesn't exist
  - `helm_repo_url`: Helm repository URL for Argo CD
  - `chart_name`: Name of the Helm chart to install
  - `chart_version`: Version of the Helm chart
  - `values`: Custom values to override Helm chart defaults

### Prometheus Module

The Prometheus module sets up Prometheus using Helm.

- **Source:** `./modules/prometheus`
- **Variables:**
  - `release_name`: Name of the Helm release for Prometheus
  - `namespace`: Namespace to install Prometheus into
  - `create_namespace`: Whether to create the namespace if it doesn't exist
  - `helm_repo_url`: Helm repository URL for Prometheus
  - `chart_name`: Name of the Helm chart to install
  - `chart_version`: Version of the Helm chart
  - `values`: Custom values to override Helm chart defaults

## Outputs

- `eks_cluster_name`: Name of the EKS cluster
- `eks_cluster_version`: Kubernetes version of the EKS cluster
- `argocd_release_namespace`: Namespace of the Argo CD Helm release
- `eks_connect`: Command to connect to the EKS cluster
- `argocd_initial_admin_secret`: Command to get the initial admin secret for Argo CD
- `argocd_server_load_balancer`: Load balancer hostname for the Argo CD server

## License

This project is licensed under the MIT License.