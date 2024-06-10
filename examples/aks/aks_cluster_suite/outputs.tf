output "cluster_token" {
  value       = var.castai_api_token
  description = "CAST AI cluster token used by Castware to atuhenticate to Mothership."
  sensitive   = true
}
