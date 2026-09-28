# Deprecated Ceph Stretch Cluster Guide

> [!WARNING]
> This filename is retained only for old links. Its former procedure used obsolete
> Proxmox/Ceph commands and an incorrect service layout. Do not execute commands from
> an older copy of this document.

Use these maintained references:

- [Production Proxmox and Ceph Network Configuration](ceph-network-configuration.md)
- [Deploy a Proxmox and Ceph Stretch Cluster from Scratch](ceph-stretch-cluster-from-scratch.md)
- [Proxmox Ceph Stretch Cluster Runbook Index](ceph-setup.md)

The supported production layout has MONs on `occ1`, `occ2`, `bocc1`, `bocc2`, and
`quorum`; managers run on data-site nodes; `quorum` has no OSD or Ceph cluster VLAN
118.
