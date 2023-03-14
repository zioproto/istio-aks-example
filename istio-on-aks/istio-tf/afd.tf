locals {
  front_door_profile_name      = "MyFrontDoor"
  front_door_endpoint_name     = "afd-${lower(random_id.front_door_endpoint_name.hex)}"
  front_door_origin_group_name = "MyOriginGroup"
  front_door_origin_name       = "IstioOrigin"
  front_door_route_name        = "MyRoute"
}

resource "random_id" "front_door_endpoint_name" {
  byte_length = 8
}

resource "azurerm_cdn_frontdoor_profile" "my_front_door" {
  depends_on          = [helm_release.istio-ingress]
  name                = local.front_door_profile_name
  resource_group_name = data.azurerm_resource_group.this.name
  sku_name            = "Premium_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "my_endpoint" {
  name                     = local.front_door_endpoint_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.my_front_door.id
}

resource "azurerm_cdn_frontdoor_origin_group" "my_origin_group" {
  name                     = local.front_door_origin_group_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.my_front_door.id
  session_affinity_enabled = true

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/probe"
    request_type        = "GET"
    protocol            = "Http"
    interval_in_seconds = 100
  }
}

data "azurerm_private_link_service" "istio-ingress" {
  depends_on                    = [helm_release.istio-ingress]
  name                          = "istio-ingress"
  resource_group_name           = join("_", ["MC", data.azurerm_resource_group.this.name , "istio-aks", data.azurerm_resource_group.this.location])
}

resource "azurerm_cdn_frontdoor_origin" "istio-ingress-origin" {
  depends_on                    = [helm_release.istio-ingress]
  name                          = local.front_door_origin_name
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.my_origin_group.id

  enabled                        = true
  host_name                      = "10.52.192.10"
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = "10.52.192.10"
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true

  private_link {
    request_message        = "Request access"
    location               = data.azurerm_resource_group.this.location
    private_link_target_id = data.azurerm_private_link_service.istio-ingress.id
  }
}

resource "azurerm_cdn_frontdoor_route" "my_route" {
  name                          = local.front_door_route_name
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.my_endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.my_origin_group.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.istio-ingress-origin.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpOnly"
  link_to_default_domain = true
  https_redirect_enabled = true
}