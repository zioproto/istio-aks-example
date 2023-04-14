variable "region" {
  type    = string
  default = "westeurope"
}

variable "agents_size" {
  default     = "Standard_D2s_v3"
  description = "The default virtual machine size for the Kubernetes agents"
  type        = string
}

variable "kubernetes_version" {
  description = "Specify which Kubernetes release to use. The default used is the latest Kubernetes version available in the region"
  type        = string
  default     = null
}

variable "rbac_aad_admin_group_object_ids" {
  description = "Object ID of Active Directory groups with admin access."
  type        = list(string)
  default     = null
}
