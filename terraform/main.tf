terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.102"
}

variable folder_id {
  type = string
  default = "b1ggt3cforeavp7a3kce"
}

variable no_of_instance {
  type = number
  default = 1
}

variable zone {
  type = string
  default = "ru-central1-a"
}

provider "yandex" {
  service_account_key_file = "./tf_key.json"
  folder_id                = var.folder_id
  zone                     = var.zone
}

data "yandex_vpc_network" "database" {
  name = "default"
}

data "yandex_vpc_subnet" "database" {
  name = "default"
}

resource "yandex_container_registry" "bingo" {
  folder_id = var.folder_id
  name = "bingo-1"
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}

locals {
  service-accounts = toset([
    "bingo-sa",
    "bingo-ig-sa",
  ])
  bingo-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor"
  ])
  bingo-ig-sa-roles = toset([
    "container-registry.images.puller",
    "compute.editor",
    "iam.serviceAccounts.user",
    "load-balancer.admin",
    "vpc.publicAdmin",
    "vpc.user"
  ])
}
resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = "${var.folder_id}-${each.key}"
}
resource "yandex_resourcemanager_folder_iam_member" "bingo-roles" {
  for_each  = local.bingo-sa-roles
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["bingo-sa"].id}"
  role      = each.key
}
resource "yandex_resourcemanager_folder_iam_member" "bingo-ig-roles" {
  for_each  = local.bingo-ig-sa-roles
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["bingo-ig-sa"].id}"
  role      = each.key
}

resource "yandex_compute_instance_group" "bingo2" {
  depends_on = [
    yandex_resourcemanager_folder_iam_member.bingo-ig-roles
  ]
  name               = "bingo"
  service_account_id = yandex_iam_service_account.service-accounts["bingo-ig-sa"].id
  allocation_policy {
    zones = [var.zone]
  }
  deploy_policy {
    max_unavailable = 1
    max_creating    = 2
    max_expansion   = 2
    max_deleting    = 2
  }
  scale_policy {
    fixed_scale {
      size = var.no_of_instance
    }
  }
  instance_template {
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["bingo-ig-sa"].id
    resources {
      cores         = 2
      memory        = 2
      core_fraction = 100
    }
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      network_id = data.yandex_vpc_network.database.id
      subnet_ids = ["${data.yandex_vpc_subnet.database.id}"]
      nat        = true
    }
    boot_disk {
      initialize_params {
        type     = "network-hdd"
        size     = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    metadata = {
      docker-compose = templatefile(
        "${path.module}/docker-compose.yaml",
        {
          folder_id   = "${var.folder_id}",
          registry_id = "${yandex_container_registry.bingo.id}",
        }
      )
      user-data = file("${path.module}/cloud-config.yaml")
      ssh-keys  = "ubuntu:${file("~/.ssh/devops_training.pub")}"
    }
  }
  load_balancer {
    target_group_name = "bingo"
  }
}

resource "yandex_lb_network_load_balancer" "lb-bingo" {
  name = "bingo"

  listener {
    name        = "http-listener"
    port        = 80
    target_port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  listener {
    name        = "https-listener"
    port        = 443
    target_port = 443
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.bingo2.load_balancer[0].target_group_id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/ping"
      }
    }
  }
}
