locals {
  # Tags match the `cloud` block of each root; CI selects the workspace with TF_WORKSPACE.
  state_workspaces = merge([
    for root in ["cluster", "platform"] : {
      for env in keys(local.environments) : "talos-${root}-${env}" => "talos-${root}"
    }
  ]...)
}

resource "tfe_workspace" "state" {
  for_each = local.state_workspaces

  name      = each.key
  tag_names = [each.value]
}

# Plans run on the CI runner, which reaches Proxmox over Tailscale; HCP Terraform only stores state.
resource "tfe_workspace_settings" "state" {
  for_each = local.state_workspaces

  workspace_id   = tfe_workspace.state[each.key].id
  execution_mode = "local"
}
