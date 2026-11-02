locals {
  controller_permissions = {
    autoscaler = [
      "compute.instanceGroupManagers.get", "compute.instanceGroupManagers.list", "compute.instanceGroupManagers.update",
      "compute.instanceGroups.get", "compute.instanceGroups.list",
      "compute.instances.get", "compute.instances.list", "compute.instanceTemplates.get", "compute.instanceTemplates.list",
      "compute.machineTypes.get", "compute.machineTypes.list", "compute.zones.get", "compute.zones.list",
      "compute.regions.get", "compute.regions.list", "compute.projects.get", "compute.zoneOperations.get",
      "compute.regionOperations.get", "compute.globalOperations.get",
    ]
    pd-csi = [
      "compute.disks.create", "compute.disks.delete", "compute.disks.get", "compute.disks.list",
      "compute.disks.resize", "compute.disks.update", "compute.disks.use", "compute.disks.useReadOnly",
      "compute.disks.setLabels", "compute.instances.attachDisk", "compute.instances.detachDisk",
      "compute.instances.get", "compute.instances.list", "compute.zones.get", "compute.zones.list",
      "compute.zoneOperations.get", "compute.regionOperations.get", "compute.globalOperations.get",
      "compute.projects.get", "compute.regions.get", "compute.regions.list",
    ]
  }
}

resource "google_service_account" "controller" {
  for_each   = local.controller_permissions
  account_id = "${var.cluster_name}-${each.key}"
}

resource "google_project_iam_custom_role" "controller" {
  for_each    = local.controller_permissions
  project     = var.project_id
  role_id     = "${replace(var.cluster_name, "-", "_")}_${replace(each.key, "-", "_")}"
  title       = "${var.cluster_name} ${each.key}"
  permissions = each.value
}

resource "google_project_iam_member" "controller" {
  for_each   = local.controller_permissions
  project    = var.project_id
  role       = google_project_iam_custom_role.controller[each.key].name
  member     = "serviceAccount:${google_service_account.controller[each.key].email}"
  depends_on = [terraform_data.storage_cleanup]
}

resource "google_service_account_key" "controller" {
  for_each           = local.controller_permissions
  service_account_id = google_service_account.controller[each.key].name
}
