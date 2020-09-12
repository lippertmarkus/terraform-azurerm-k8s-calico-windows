# terraform-azurerm-k8s-calico-windows

Terraform definition for trying out [Calico for Windows](https://docs.projectcalico.org/getting-started/windows-calico/) in a self-managed Kubernetes cluster on Azure with both a Linux and a Windows Server 1903 node for testing purposes. Find more details in the [blog post](TODO) (coming soon).

## Deployment on Azure

You need to install [Terraform](https://www.terraform.io/) as well as the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-windows?view=azure-cli-latest&tabs=azure-cli) first. Then execute the following in the directory of the cloned repository:
```bash
az login  # log in to your Azure account
terraform init  # initialize terraform
terraform apply -auto-approve  # provision infrastructure
```

## Interact with the cluster

After the deployment you can SSH to the primary node and deploy an example Windows container workload:
```bash
ssh -i output/primary_pk azadmin@$(terraform output primary_ip)
kubectl get node
kubectl get pod -A
kubectl apply -f https://raw.githubusercontent.com/lippertmarkus/terraform-azurerm-k8s-calico-windows/master/example_workloads/win-webserver.yml
```

You can also follow the [blog post](TODO) (coming soon) to see how network policies work with Calico.