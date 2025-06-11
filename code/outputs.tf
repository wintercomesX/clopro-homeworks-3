# outputs.tf
output "public_vm_ip" {
  description = "Public VM's IP address"
  value       = yandex_compute_instance.public_vm.network_interface[0].ip_address
}

output "private_vm_ip" {
  description = "Private VM's IP address"
  value       = yandex_compute_instance.private_vm.network_interface[0].ip_address
}

# Object Storage outputs
output "bucket_name" {
  description = "Name of the created storage bucket"
  value       = yandex_storage_bucket.image_bucket.bucket
}

output "bucket_domain_name" {
  description = "Domain name of the bucket"
  value       = yandex_storage_bucket.image_bucket.bucket_domain_name
}

output "image_public_url" {
  description = "Public URL of the uploaded image"
  value       = "https://${yandex_storage_bucket.image_bucket.bucket_domain_name}/${var.image_filename}"
}

output "storage_access_key" {
  description = "Access key for Object Storage"
  value       = yandex_iam_service_account_static_access_key.storage_key.access_key
  sensitive   = true
}

output "storage_secret_key" {
  description = "Secret key for Object Storage"
  value       = yandex_iam_service_account_static_access_key.storage_key.secret_key
  sensitive   = true
}

# KMS Key outputs
output "kms_key_id" {
  description = "ID of the KMS symmetric key"
  value       = yandex_kms_symmetric_key.storage_key.id
}

output "kms_key_name" {
  description = "Name of the KMS symmetric key"
  value       = yandex_kms_symmetric_key.storage_key.name
}

output "kms_key_status" {
  description = "Status of the KMS symmetric key"
  value       = yandex_kms_symmetric_key.storage_key.status
}

output "bucket_encryption_status" {
  description = "Encryption configuration of the storage bucket"
  value       = "Encrypted with KMS key: ${yandex_kms_symmetric_key.storage_key.name}"
}

# Instance Group outputs
output "instance_group_id" {
  description = "ID of the Instance Group"
  value       = yandex_compute_instance_group.lamp_group.id
}

output "instance_group_instances" {
  description = "List of instances in the group"
  value       = yandex_compute_instance_group.lamp_group.instances
}

output "lamp_servers_ips" {
  description = "External IP addresses of LAMP servers"
  value       = [for instance in yandex_compute_instance_group.lamp_group.instances : instance.network_interface[0].nat_ip_address if instance.network_interface[0].nat_ip_address != ""]
}

output "lamp_servers_urls" {
  description = "URLs of LAMP servers"
  value       = [for instance in yandex_compute_instance_group.lamp_group.instances : "http://${instance.network_interface[0].nat_ip_address}" if instance.network_interface[0].nat_ip_address != ""]
}

# Load Balancer outputs
output "load_balancer_ip" {
  description = "External IP address of the Network Load Balancer"
  value       = one([for listener in yandex_lb_network_load_balancer.lamp_balancer.listener : one(listener.external_address_spec).address if length(listener.external_address_spec) > 0])
}

output "load_balancer_url" {
  description = "URL of the Network Load Balancer"
  value       = "http://${one([for listener in yandex_lb_network_load_balancer.lamp_balancer.listener : one(listener.external_address_spec).address if length(listener.external_address_spec) > 0])}"
}

output "target_group_id" {
  description = "ID of the Target Group"
  value       = yandex_lb_target_group.lamp_target_group.id
}

output "load_balancer_id" {
  description = "ID of the Network Load Balancer"
  value       = yandex_lb_network_load_balancer.lamp_balancer.id
}
