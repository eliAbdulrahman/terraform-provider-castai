## GKE and CAST AI example with CAST AI Autoscaler policies and additional Node Configurations

Following example shows how to onboard GKE cluster to CAST AI, configure [Autoscaler policies](https://docs.cast.ai/reference/policiesapi_upsertclusterpolicies), additional [Node Configurations](https://docs.cast.ai/docs/node-configuration/) and set the cast-pool nodepool to it's own address range.

IAM policies required to connect the cluster to CAST AI in the example are created by [castai/gke-role-iam/castai module](https://github.com/castai/terraform-castai-gke-iam).

Example configuration should be analysed in the following order:
1. Create VPC - `vpc.tf`
2. Create GKE cluster - `gke.tf`
3. Create IAM and other CAST AI related resources to connect GKE cluster to CAST AI, configure Autoscaler and Node Configurations  - `castai.tf`

# Usage
1. Rename `tf.vars.example` to `tf.vars`
2. Update `tf.vars` file with your project name, cluster name, cluster region and CAST AI API token.
3. Initialize Terraform. Under example root folder run:
```
terraform init
```
4. Run Terraform apply:
```
terraform apply -var-file=tf.vars
```

4b. Once the cast-pool is created. The `alt-temp-pool` can be deleted

5. To destroy resources created by this example:
```
terraform destroy -var-file=tf.vars
```

Please refer to this guide if you run into any issues https://docs.cast.ai/docs/terraform-troubleshooting
