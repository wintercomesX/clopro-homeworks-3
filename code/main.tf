# Create VPC
resource "yandex_vpc_network" "vpc" {
  folder_id = "b1gghnpp51joeriep6bo"
  name      = "my-vpc"
  labels = {
    environment = "dev"
  }
}

# Create public subnet
resource "yandex_vpc_subnet" "public" {
  folder_id       = "b1gghnpp51joeriep6bo"
  network_id      = yandex_vpc_network.vpc.id
  name            = "public"
  zone            = var.region
  v4_cidr_blocks = ["192.168.10.0/24"]
}

# Create route table for private subnet
resource "yandex_vpc_route_table" "private_route_table" {
  name       = "private-route-table"
  network_id = yandex_vpc_network.vpc.id
  static_route {
    destination_prefix = "0.0.0.0/0"
    next_hop_address   = "192.168.10.254"
  }
}

# Create private subnet and associate route table
resource "yandex_vpc_subnet" "private" {
  folder_id       = "b1gghnpp51joeriep6bo"
  network_id      = yandex_vpc_network.vpc.id
  name            = "private"
  zone            = var.region
  v4_cidr_blocks = ["192.168.20.0/24"]
  route_table_id  = yandex_vpc_route_table.private_route_table.id
}

# NAT Instance
resource "yandex_compute_instance" "nat" {
  name        = "nat-instance"
  zone        = var.region
  platform_id = "standard-v1"
  resources {
    cores  = 2
    memory = 4
  }
  boot_disk {
    initialize_params {
      image_id = "fd80mrhj8fl2oe87o4e1"
    }
  }
  network_interface {
    subnet_id  = yandex_vpc_subnet.public.id
    ip_address = "192.168.10.254"  # Static IP for NAT
    nat        = true
  }
  metadata = {
    serial-port-enable = 1
    ssh-keys = "ubuntu:${var.ssh_public_key}"
  }
}

# Public VM
resource "yandex_compute_instance" "public_vm" {
  name        = "public-vm"
  zone        = var.region
  platform_id = "standard-v1"
  resources {
    cores  = 2
    memory = 4
  }
  boot_disk {
    initialize_params {
      image_id = "fd8aus3bfglr6dg9hsbk"
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.public.id
    nat       = true
  }
  metadata = {
    serial-port-enable = 1
    ssh-keys = "ubuntu:${var.ssh_public_key}"
  }
}

# Private VM
resource "yandex_compute_instance" "private_vm" {
  name        = "private-vm"
  zone        = var.region
  platform_id = "standard-v1"
  resources {
    cores  = 2
    memory = 4
  }
  boot_disk {
    initialize_params {
      image_id = "fd8aus3bfglr6dg9hsbk"
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.private.id
    nat       = false
  }
  metadata = {
    serial-port-enable = 1
    ssh-keys = "ubuntu:${var.ssh_public_key}"
  }
}

# Create KMS Symmetric Key for Object Storage encryption
resource "yandex_kms_symmetric_key" "storage_key" {
  name              = "storage-encryption-key"
  description       = "KMS key for Object Storage bucket encryption"
  default_algorithm = "AES_256"
  rotation_period   = "8760h" # 1 year
  
  labels = {
    environment = "dev"
    purpose     = "storage-encryption"
  }
}

# Create service account for Object Storage
resource "yandex_iam_service_account" "storage_sa" {
  name        = "storage-service-account"
  description = "Service account for Object Storage operations"
}

# Create access key for service account
resource "yandex_iam_service_account_static_access_key" "storage_key" {
  service_account_id = yandex_iam_service_account.storage_sa.id
  description        = "Static access key for Object Storage"
}

# Assign storage.admin role to service account
resource "yandex_resourcemanager_folder_iam_member" "storage_editor" {
  folder_id = "b1gghnpp51joeriep6bo"
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.storage_sa.id}"
}

# Assign KMS encrypter/decrypter role to storage service account
resource "yandex_resourcemanager_folder_iam_member" "storage_kms_keys_encrypter" {
  folder_id = "b1gghnpp51joeriep6bo"
  role      = "kms.keys.encrypterDecrypter"
  member    = "serviceAccount:${yandex_iam_service_account.storage_sa.id}"
}

# Create Object Storage bucket with KMS encryption
resource "yandex_storage_bucket" "image_bucket" {
  bucket     = var.bucket_name
  access_key = yandex_iam_service_account_static_access_key.storage_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.storage_key.secret_key
  
  # Add server-side encryption configuration
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = yandex_kms_symmetric_key.storage_key.id
        sse_algorithm     = "aws:kms"
      }
    }
  }
  
  # Wait for IAM role assignments
  depends_on = [
    yandex_resourcemanager_folder_iam_member.storage_editor,
    yandex_resourcemanager_folder_iam_member.storage_kms_keys_encrypter
  ]
}

# Upload image to bucket (will be automatically encrypted by bucket KMS configuration)
resource "yandex_storage_object" "image_file" {
  bucket     = yandex_storage_bucket.image_bucket.bucket
  key        = var.image_filename
  source     = var.image_file_path
  access_key = yandex_iam_service_account_static_access_key.storage_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.storage_key.secret_key
  
  # Set content type for image
  content_type = "image/jpeg"
  
  # Make object publicly readable
  acl = "public-read"
  
  # Ensure bucket is ready with encryption configuration
  depends_on = [yandex_storage_bucket.image_bucket]
}

# Create service account for Instance Group
resource "yandex_iam_service_account" "ig_sa" {
  name        = "instance-group-service-account"
  description = "Service account for Instance Group operations"
}

# Assign compute.editor role to service account
resource "yandex_resourcemanager_folder_iam_member" "ig_editor" {
  folder_id = "b1gghnpp51joeriep6bo"
  role      = "compute.editor"
  member    = "serviceAccount:${yandex_iam_service_account.ig_sa.id}"
}

# Assign vpc.publicAdmin role to service account
resource "yandex_resourcemanager_folder_iam_member" "ig_vpc_admin" {
  folder_id = "b1gghnpp51joeriep6bo"
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.ig_sa.id}"
}

# Local value for bucket domain to avoid circular dependency
locals {
  bucket_domain = "${var.bucket_name}.storage.yandexcloud.net"
}

# Create Instance Group with LAMP template
resource "yandex_compute_instance_group" "lamp_group" {
  name                = "lamp-instance-group"
  service_account_id  = yandex_iam_service_account.ig_sa.id
  deletion_protection = false
  
  # Wait for IAM roles to be assigned
  depends_on = [
    yandex_resourcemanager_folder_iam_member.ig_editor,
    yandex_resourcemanager_folder_iam_member.ig_vpc_admin
  ]
  
  instance_template {
    platform_id = "standard-v1"
    
    resources {
      cores  = 2
      memory = 4
    }
    
    boot_disk {
      mode = "READ_WRITE"
      initialize_params {
        image_id = "fd827b91d99psvq5fjit"  # LAMP image
        size     = 13
      }
    }
    
    network_interface {
      network_id = yandex_vpc_network.vpc.id
      subnet_ids = [yandex_vpc_subnet.public.id]
      nat        = true
    }
    
    metadata = {
      serial-port-enable = 1
      ssh-keys = "ubuntu:${var.ssh_public_key}"
      user-data = templatefile("${path.module}/user-data.sh", {
        bucket_domain = local.bucket_domain
        image_filename = var.image_filename
      })
    }
  }
  
  scale_policy {
    fixed_scale {
      size = 3
    }
  }
  
  allocation_policy {
    zones = [var.region]
  }
  
  deploy_policy {
    max_unavailable = 1
    max_expansion   = 0
  }
  
  # Health check configuration
  health_check {
    timeout = 10
    interval = 30
    healthy_threshold = 5
    unhealthy_threshold = 2
    
    http_options {
      port = 80
      path = "/health"
    }
  }
}

# Create Target Group for Load Balancer
resource "yandex_lb_target_group" "lamp_target_group" {
  name      = "lamp-target-group"
  region_id = "ru-central1"
  
  dynamic "target" {
    for_each = yandex_compute_instance_group.lamp_group.instances
    content {
      subnet_id = target.value.network_interface[0].subnet_id
      address   = target.value.network_interface[0].ip_address
    }
  }
}

# Create Network Load Balancer
resource "yandex_lb_network_load_balancer" "lamp_balancer" {
  name = "lamp-network-load-balancer"
  
  listener {
    name = "lamp-listener"
    port = 80
    protocol = "tcp"
    target_port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }
  
  attached_target_group {
    target_group_id = yandex_lb_target_group.lamp_target_group.id
    
    healthcheck {
      name = "http"
      interval = 15
      timeout = 10
      unhealthy_threshold = 5
      healthy_threshold = 2
      http_options {
        port = 80
        path = "/health"
      }
    }
  }
}

