# TrueNAS Storage Configuration Guide

TrueNAS provides persistent storage for homelab services. Application files and database data are stored in separate pools.

**Table of Contents:**

1. [Storage Architecture](#1-storage-architecture)
2. [Immich Database Application](#2-immich-database-application)
3. [NFS Shares and VM Mounts](#3-nfs-shares-and-vm-mounts)

---

## 1. Storage Architecture

* **Mass-storage pool:** Holds the Immich library and Vaultwarden persistent data, mounted on `ts_vm`.
* **Separate SSD pool:** Holds database datasets. The owner runs application databases on TrueNAS and maps their persistent storage to datasets in this pool.
* **Immich machine-learning cache:** Also stored on TrueNAS and bind-mounted on `ts_vm`.

## 2. Immich Database Application

Immich's PostgreSQL application stores its persistent data in a dataset on the separate SSD pool. It is deployed as a custom TrueNAS application and accessed by Immich on `ts_vm`.

See [Deploying the Immich Database on TrueNAS](../ts_vm/README.md#42-deploying-the-immich-database-on-truenas) in the TS VM guide for image configuration, persistent storage, and VM connection settings.

---

## 3. NFS Shares and VM Mounts

The [CF VM guide](../cf_vm/README.md#41-preparing-nfs-shares-in-truenas) already covers the general share preparation and mounting workflow. The [TS VM guide](../ts_vm/README.md#41-preparing-and-mounting-truenas-storage) covers its application dependencies.
