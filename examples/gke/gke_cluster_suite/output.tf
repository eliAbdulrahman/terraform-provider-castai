output "cluster_id" {
  value       = castai_gke_cluster.this.id
  description = "CAST AI cluster ID."
}

output "cluster_token" {
  value       = castai_gke_cluster.this.cluster_token
  description = "CAST AI cluster token used by Castware to authenticate to Mothership."
  sensitive   = true
}

output "private_key" {
  value     = module.castai-gke-iam.private_key
  sensitive = true
}

output "service_account_id" {
  value = module.castai-gke-iam.service_account_id
}

output "service_account_email" {
  value = module.castai-gke-iam.service_account_email
}
