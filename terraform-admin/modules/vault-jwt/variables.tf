variable "env" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

variable "jwt_backend_path" {
  description = "Path of the shared JWT auth backend"
  type        = string
}

variable "github_organization" {
  type        = string
  description = "The GitHub organization name."
}

variable "github_repository" {
  type        = string
  description = "The GitHub repository name."
}

variable "github_owner_id" {
  type        = string
  description = "Numeric GitHub owner ID (immutable OIDC sub uses owner@id)."
}

variable "github_repository_id" {
  type        = string
  description = "Numeric GitHub repository ID (immutable OIDC sub uses repo@id)."
}

variable "github_branch" {
  type        = string
  description = "The GitHub branch name to restrict access to."
}
