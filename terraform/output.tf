output "container_registry_id" {
  value = yandex_container_registry.bingo.id
}

output "lb_ip_address" {
  value = [for addr in yandex_lb_network_load_balancer.lb-bingo.listener: addr.external_address_spec]
}

output "bingo_group" {
  value = [for net in yandex_compute_instance_group.bingo2.instances: net.network_interface]
}