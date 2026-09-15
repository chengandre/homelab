# TrueNAS Storage Configuration Guide

TrueNAS provides persistent storage and hosts database applications for services running on the homelab VMs. Application files and database data use separate pools. The deployed TrueNAS version is **24.10.2.1**.

**Table of Contents:**

1. [Storage Architecture](#1-storage-architecture)
2. [TS VM](#2-ts-vm)
   * [Immich](#21-immich)
     * [Mass-Storage Dataset](#211-mass-storage-dataset)
     * [NFS Share](#212-nfs-share)
     * [PostgreSQL Dataset and Deployment](#213-postgresql-dataset-and-deployment)
   * [Vaultwarden](#22-vaultwarden)
     * [Mass-Storage Dataset](#221-mass-storage-dataset)
     * [NFS Share](#222-nfs-share)
3. [CF VM](#3-cf-vm)
   * [Nextcloud](#31-nextcloud)
     * [MariaDB Dataset and Deployment](#311-mariadb-dataset-and-deployment)
     * [Mass-Storage Dataset](#312-mass-storage-dataset)
     * [NFS Share](#313-nfs-share)
   * [Paperless-ngx](#32-paperless-ngx)
     * [Mass-Storage Dataset](#321-mass-storage-dataset)
     * [NFS Share](#322-nfs-share)
     * [MariaDB Connection](#323-mariadb-connection)

---

## 1. Storage Architecture

* **Mass-storage pool:** Holds application files exported to the VMs through NFS.
* **Separate SSD pool:** Holds database datasets mounted directly into database applications running on TrueNAS. VM services connect to the databases through their published ports.

Replace `<MASS_STORAGE_POOL>` and `<SSD_POOL>` with your pool names. The application sections cover storage creation and TrueNAS deployments; the VM guides cover client mounts, Docker stacks, and service access.

## 2. TS VM

Complete the storage and database steps below before deploying the [TS VM stack](../ts_vm/README.md#43-deploying-the-docker-stack). Use `<TS_VM_IP>` for the VM's LAN IPv4 address. Numeric account IDs use placeholders.

### 2.1 Immich

Immich's library and machine-learning cache share one mass-storage dataset and NFS export. Its PostgreSQL data is stored separately on the SSD pool.

#### 2.1.1 Mass-Storage Dataset

1. **Create the Storage User:** In the **TrueNAS web interface → Credentials → Users → Add**, enter your desired **Full Name**, for example `Immich`, and **Username**, for example `immich`. Select **Create New Primary Group** to create a group matching your chosen username, choose an available UID, then save the account. This account supplies filesystem ownership and numeric IDs for application access.
2. **Record the IDs:** In the **TrueNAS shell**, run:

   ```bash
   id immich
   ```

   Replace `immich` with your chosen username.

   Record the UID as `<IMMICH_UID>` and the primary GID as `<IMMICH_GID>`. Use the IDs from the created account when configuring application access; do not assume the UID and GID are equal.
3. **Create the Dataset:** In **Datasets**, select the dataset for this VM, for example `<MASS_STORAGE_POOL>/ts_vm`, and click **Add Dataset**. Enter your desired **Name**, for example `Immich`. For a new dataset using the Unix permissions below, select **Generic** as **Dataset Preset**. See [TrueNAS dataset creation](https://www.truenas.com/docs/scale/24.10/scaletutorials/datasets/datasetsscale/).
4. **Set Dataset Properties:** In **Advanced Options**, choose properties for your storage needs. This setup uses **Sync: Standard**, **Compression: Inherit (LZ4)**, **Atime: Off**, **Deduplication: Off**, and case-sensitive names. Save the dataset. Its example path is `<MASS_STORAGE_POOL>/ts_vm/Immich`.
5. **Assign Ownership:** Select the new dataset and click **Edit** in **Permissions**. In the Unix permissions editor, set **User** and **Group** to the storage account and group you created (`immich` in these examples). Select **Apply User** and **Apply Group**.
6. **Set Permissions:** Give **User** read, write, and execute; **Group** read and execute; and **Other** no permissions. Save. This is Unix mode **750**. These steps configure the new dataset; recursively changing existing application files is a separate operation. See the [TrueNAS permissions editor](https://www.truenas.com/docs/scale/24.10/scaleuireference/datasets/editaclscreens/).
7. **Optionally Limit Storage:** To cap storage usage, open **Dataset Space Management → Edit** and choose a dataset quota, for example **1 TiB**, including descendants. You can leave the dataset without a quota. User and group quotas are separate settings.
8. **Verify the Dataset:** Reopen the dataset and confirm its path, ownership by your storage user and group, Unix permissions, properties, and any quota you configured before creating the NFS share.

#### 2.1.2 NFS Share

1. **Add the Share:** In the **TrueNAS web interface → Shares → NFS**, click **Add** and select the dataset you created as **Path**, for example `/mnt/<MASS_STORAGE_POOL>/ts_vm/Immich`.
2. **Set Access Options:** Leave **Description** empty, check **Enabled**, and leave **Read Only** unchecked. Set **Maproot User** and **Maproot Group** to your storage account and group (`immich` in these examples). Leave **Mapall User** and **Mapall Group** unset, and leave **Security** without an explicit selection.
3. **Restrict the Client:** In **Networks**, add `<TS_VM_IP>` with prefix length **32**. Use the TS VM's LAN address; the `/32` entry selects that single IPv4 address. Use Maproot rather than Mapall for this share.
4. **Verify the Share:** Save, reopen the share, and confirm the export path, enabled state, writable setting, client entry, and user/group mappings.

Continue with [TS VM storage mounting](../ts_vm/README.md#41-preparing-and-mounting-truenas-storage), using this export path. TrueNAS paths, VM mount points, and container paths are distinct.

The single Immich export contains both the library and model-cache data. Bind-mount their respective directories into the containers from the mounted dataset.

#### 2.1.3 PostgreSQL Dataset and Deployment

The TrueNAS PostgreSQL application uses a database dataset on the SSD pool, mounted locally into the container. It is separate from the VM's NFS storage.

1. **Create the Database Dataset:** In the **TrueNAS web interface → Datasets**, select your SSD pool's database parent dataset (`DB` in this example) and click **Add Dataset**. Enter your desired **Name**, for example `Postgresql`, and save with the database storage settings. The deployed dataset uses **Sync: Standard**, inherited **LZ4**, **Atime: Off**, **Deduplication: Off**, and case-sensitive names.
2. **Review Database Permissions:** Select the database dataset and open **Permissions → Edit**. The deployed dataset uses an **NFSv4 ACL**, with displayed owner `netdata` and group `root`. Its visible entries are:

   | ACL entry | Access | Permissions |
   |---|---|---|
   | `owner@` (`netdata`) | Allow | Full Control |
   | `group@` (`root`) | Allow | Modify |
   | Group `builtin_users` | Allow | Modify |
   | Group `builtin_administrators` | Allow | Full Control |
   | User `apps` | Allow | Modify |
   | Additional `owner@` (`netdata`) | Allow | Special |
   | Additional `group@` (`root`) | Allow | Special |
   | `everyone@` | Allow | Special |

   Review permissions and inheritance flags for the complete ACL, including the advanced rights represented by Special entries. The displayed dataset owner does not establish the database container's runtime UID.
3. **Open the Custom App Wizard:** In the **TrueNAS web interface → Apps → Discover Apps → Custom App**, enter your desired **Application Name**, for example `postgresql`. Use the guided form shown as **Install iX App**; an existing application's edit form is titled **Edit iX App**. See [TrueNAS custom app installation](https://apps.truenas.com/managing-apps/installing-custom-apps/).
4. **Configure the Image:** In **Image Configuration**, enter:

   | Field | Value |
   |---|---|
   | Repository | `ghcr.io/immich-app/postgres` |
   | Tag used in this deployment | `14-vectorchord0.3.0-pgvectors0.2.0` |
   | Pull Policy | Pull the image if it is not already present on the host |

   Use a database image compatible with your Immich release. The tag above records this deployment; check your release's database requirements before choosing another tag.
5. **Configure the Container:** In **Container Configuration**, leave **Hostname** empty and add no **Entrypoint** or **Command** overrides. Choose your **Timezone** and set **Restart Policy** to **Unless Stopped**. Leave **Disable Builtin Healthcheck**, **TTY**, and **Stdin** unchecked, and add no devices.
6. **Add Initialization Variables:** In the form's environment-variable list, add one entry for each variable:

   | Variable | Value to enter | Purpose |
   |---|---|---|
   | `POSTGRES_PASSWORD` | `<IMMICH_DB_PASSWORD>` | Choose a strong database password; use the same value for the VM's `DB_PASSWORD` |
   | `POSTGRES_USER` | `<IMMICH_DB_USER>` | Choose a database username, for example `immich`; use it for `DB_USERNAME` |
   | `POSTGRES_DB` | `<IMMICH_DB_NAME>` | Choose a database name, for example `immich`; use it for `DB_DATABASE_NAME` |
   | `POSTGRES_INITDB_ARGS` | `--data-checksums` | Enable data-page checksums during database initialization |

   Enter your chosen values in place of the placeholders. The database username is a PostgreSQL role, separate from the TrueNAS storage account and container's operating-system user. These initialization variables apply to an empty data directory; changing them on an existing database does not recreate its users, password, database, or checksum configuration. See the [PostgreSQL image environment reference](https://hub.docker.com/_/postgres).
7. **Configure the Security Context:** Leave **Privileged** and **Custom User** unchecked and add no extra **Capabilities**. This uses the image's normal user handling; do not enter the mass-storage account IDs here.
8. **Publish the Database Port:** In **Network Configuration**, leave **Host Network** unchecked. Under **Ports → Add**, enter:

   | Field | Value |
   |---|---|
   | Container Port | `5432` |
   | Host Port | Choose an available port, for example `5432` |
   | Protocol | `TCP` |

   Record your chosen host port as `<PUBLISHED_POSTGRES_PORT>` for the VM's `DB_PORT`. Immich connects to `<TRUENAS_IP>` at this host port, not to the container's private address. Leave **Nameservers** and **Search Domains** empty under **Custom DNS Setup**, and add no **Portal Configuration** entries; PostgreSQL has no web interface.
9. **Map Persistent Storage:** In **Storage → Add**, configure:

   | Field | Value |
   |---|---|
   | Type | Host Path (Path that already exists on the system) |
   | Read Only | Unchecked |
   | Mount Path | `/var/lib/postgresql/data` |
   | Enable ACL | Unchecked |
   | Host Path | Select the database dataset created above, for example `/mnt/<SSD_POOL>/DB/Postgresql` |

   The mount path is the container destination for the configured PostgreSQL 14 image. The host path is local to TrueNAS and belongs on the SSD pool. **Enable ACL** here is an application mount option; leaving it unchecked does not remove the dataset's existing NFSv4 ACL.
10. **Optionally Set Resource Limits:** In **Resources Configuration**, enable **Enable Resource Limits** if you want to cap the application's resources. Choose limits for your workload; this deployment uses **CPUs: 2** and **Memory (in MB): 4096**. Leave GPU passthrough unchecked and add no **Labels Configuration** entries.
11. **Deploy and Check Startup:** Review the form and install the application. In **Apps**, select it and inspect its status and container logs. Expect it to remain running and PostgreSQL to report that it is ready to accept connections, with no initialization or storage-permission errors.
12. **Verify the Database:** Open the PostgreSQL container's **Shell** from its application page. Replace the username and database placeholders below with the values entered in Step 6:

   ```bash
   pg_isready -h 127.0.0.1 -p 5432
   psql -U '<IMMICH_DB_USER>' -d '<IMMICH_DB_NAME>' -c 'SELECT current_database(), current_user;'
   psql -U '<IMMICH_DB_USER>' -d '<IMMICH_DB_NAME>' -c 'SHOW data_checksums;'
   ```

   Expect `accepting connections`, your chosen database and user, and `data_checksums` set to `on` for a fresh database initialized with the configured argument. This checks the database inside its container; verify the VM connection separately after deploying Immich.

After the database is ready, return to [TS VM database connection settings](../ts_vm/README.md#42-configuring-the-immich-database-connection). The VM's `DB_*` variables configure its connection; they do not initialize the TrueNAS database.

### 2.2 Vaultwarden

Vaultwarden's persistent data lives in its own mass-storage dataset and writable NFS export.

#### 2.2.1 Mass-Storage Dataset

1. **Create the Storage User:** In the **TrueNAS web interface → Credentials → Users → Add**, enter your desired **Full Name**, for example `Vaultwarden`, and **Username**, for example `vaultwar`. Select **Create New Primary Group** to create a group matching your chosen username, choose an available UID, then save the account. This account supplies filesystem ownership and numeric IDs for application access.
2. **Record the IDs:** In the **TrueNAS shell**, run:

   ```bash
   id vaultwar
   ```

   Replace `vaultwar` with your chosen username.

   Record the UID as `<VAULTWARDEN_UID>` and the primary GID as `<VAULTWARDEN_GID>`. Use the IDs from the created account when configuring application access; do not assume the UID and GID are equal.
3. **Create the Dataset:** In **Datasets**, select the dataset for this VM, for example `<MASS_STORAGE_POOL>/ts_vm`, and click **Add Dataset**. Enter your desired **Name**, for example `Vaultwarden`. For a new dataset using the Unix permissions below, select **Generic** as **Dataset Preset**. See [TrueNAS dataset creation](https://www.truenas.com/docs/scale/24.10/scaletutorials/datasets/datasetsscale/).
4. **Set Dataset Properties:** In **Advanced Options**, choose properties for your storage needs. This setup uses **Sync: Standard**, **Compression: Inherit (LZ4)**, **Atime: Off**, **Deduplication: Off**, and case-sensitive names. Save the dataset. Its example path is `<MASS_STORAGE_POOL>/ts_vm/Vaultwarden`.
5. **Assign Ownership:** Select the new dataset and click **Edit** in **Permissions**. In the Unix permissions editor, set **User** and **Group** to the storage account and group you created (`vaultwar` in these examples). Select **Apply User** and **Apply Group**.
6. **Set Permissions:** Give **User** read, write, and execute; **Group** read and execute; and **Other** no permissions. Save. This is Unix mode **750**. These steps configure the new dataset; recursively changing existing application files is a separate operation. See the [TrueNAS permissions editor](https://www.truenas.com/docs/scale/24.10/scaleuireference/datasets/editaclscreens/).
7. **Optionally Limit Storage:** To cap storage usage, open **Dataset Space Management → Edit** and choose a dataset quota, for example **5 GiB**, including descendants. You can leave the dataset without a quota. User and group quotas are separate settings.
8. **Verify the Dataset:** Reopen the dataset and confirm its path, ownership by your storage user and group, Unix permissions, properties, and any quota you configured before creating the NFS share.

#### 2.2.2 NFS Share

1. **Add the Share:** In the **TrueNAS web interface → Shares → NFS**, click **Add** and select the dataset you created as **Path**, for example `/mnt/<MASS_STORAGE_POOL>/ts_vm/Vaultwarden`.
2. **Set Access Options:** Leave **Description** empty, check **Enabled**, and leave **Read Only** unchecked. Set **Maproot User** and **Maproot Group** to your storage account and group (`vaultwar` in these examples). Leave **Mapall User** and **Mapall Group** unset, and leave **Security** without an explicit selection.
3. **Restrict the Client:** In **Networks**, add `<TS_VM_IP>` with prefix length **32**. Use the TS VM's LAN address; the `/32` entry selects that single IPv4 address. Use Maproot rather than Mapall for this share.
4. **Verify the Share:** Save, reopen the share, and confirm the export path, enabled state, writable setting, client entry, and user/group mappings.

Continue with [TS VM storage mounting](../ts_vm/README.md#41-preparing-and-mounting-truenas-storage), using this export path. TrueNAS paths, VM mount points, and container paths are distinct.

After mounting storage, continue with [Vaultwarden configuration on TS VM](../ts_vm/README.md#52-vaultwarden).

## 3. CF VM

TrueNAS provides NFS-backed application storage and database applications for services on `cf_vm`. Complete the relevant database setup before deploying the [CF VM Docker stack](../cf_vm/README.md#43-deploying-the-docker-stack).

### 3.1 Nextcloud

Nextcloud runs on `cf_vm` and connects to MariaDB on TrueNAS. Its application files use the VM's mounted storage; MariaDB's database files remain local to the SSD pool on TrueNAS.

#### 3.1.1 MariaDB Dataset and Deployment

One MariaDB application on TrueNAS serves both Nextcloud and Paperless on `cf_vm`, each with its own database name and database user. Deploy the dataset and application once; Paperless reuses this server through its [database connection settings](#323-mariadb-connection). The initialization variables below create one application database/account on a fresh server, not both applications' database configurations.

1. **Create the Database Dataset:** In the **TrueNAS web interface → Datasets**, select your SSD pool's database parent dataset, for example `<SSD_POOL>/DB`, and click **Add Dataset**. Enter your desired **Name**, for example `MariaDB`. Its example host path is `/mnt/<SSD_POOL>/DB/MariaDB`.
2. **Set Dataset Properties:** In **Advanced Options**, choose properties for your storage needs. This deployment uses **Sync: Standard**, **Compression: Inherit (LZ4)**, **Atime: Off**, **Deduplication: Off**, and case-sensitive names. Save, then reopen the dataset to verify its path and properties.
3. **Review Database Permissions:** Select the dataset and open **Permissions → Edit**. The deployed MariaDB dataset uses an **NFSv4 ACL**, with displayed owner `netdata` and group `docker`. Its visible ACL entries are:

   | ACL entry | Access | Permissions |
   |---|---|---|
   | `owner@` (`netdata`) | Allow | Full Control |
   | `group@` (`docker`) | Allow | Modify |
   | Group `builtin_users` | Allow | Modify |
   | Group `builtin_administrators` | Allow | Full Control |
   | User `apps` | Allow | Modify |

   The displayed owner/group describe this dataset; confirm the database container's numeric operating-system identity before assigning ownership on a new installation. Review permissions and inheritance flags for the complete ACL. The database role created with `MYSQL_USER` does not set filesystem ownership.
4. **Open the Custom App Wizard:** In **Apps → Discover Apps → Custom App**, enter your desired **Application Name**, for example `mariadb`.
5. **Configure the Image:** In **Image Configuration**, enter:

   | Field | Value |
   |---|---|
   | Repository | `mariadb` |
   | Tag used in this deployment | `lts` |
   | Pull Policy | Pull the image if it is not already present on the host |

   The `lts` tag is the configured image tag, rather than a confirmed running server version. Choose a MariaDB version supported by your Nextcloud release.
6. **Configure the Container:** In **Container Configuration**, choose your local **Timezone** from the dropdown. Leave **Hostname** empty and add no **Entrypoint** override. Keep the remaining container options, security context, custom DNS, portal, and label settings at their wizard defaults. Under **Command → Add**, enter one argument:

   ```text
   --transaction-isolation=READ-COMMITTED
   ```

   This sets the database's transaction isolation for Nextcloud. See [Nextcloud's database configuration guidance](https://docs.nextcloud.com/server/stable/admin_manual/configuration_database/linux_database_configuration.html).
7. **Add Initialization Variables:** Add one environment-variable entry for each of the following:

   | Variable | Value to enter | Purpose |
   |---|---|---|
   | `MYSQL_ROOT_PASSWORD` | `<MARIADB_ROOT_PASSWORD>` | Choose a strong password for the MariaDB root account |
   | `MYSQL_PASSWORD` | `<NEXTCLOUD_DB_PASSWORD>` | Choose the application database user's password |
   | `MYSQL_DATABASE` | `<NEXTCLOUD_DB_NAME>` | Choose a database name, for example `nextcloud` |
   | `MYSQL_USER` | `<NEXTCLOUD_DB_USER>` | Choose an application database username, for example `nextcloud` |

   Enter your chosen values in place of the placeholders. `MYSQL_USER` creates a database account with access to `MYSQL_DATABASE`; it is separate from the TrueNAS dataset owner. Use this application account for Nextcloud. The `MYSQL_*` initialization variables are supported by the MariaDB image and configure a fresh database; changing them does not reset an existing database's users or passwords. See the [MariaDB image environment reference](https://mariadb.com/docs/server/server-management/install-and-upgrade-mariadb/installing-mariadb/binary-packages/automated-mariadb-deployment-and-administration/docker-and-mariadb/mariadb-server-docker-official-image-environment-variables).
8. **Publish the Database Port:** In **Network Configuration**, leave **Host Network** unchecked. Under **Ports → Add**, enter:

   | Field | Value |
   |---|---|
   | Container Port | `3306` |
   | Host Port | Choose an available port, for example `3306` |
   | Protocol | `TCP` |

   Record the host port as `<PUBLISHED_MARIADB_PORT>`. Nextcloud connects to `<TRUENAS_IP>` at this port.
9. **Map Persistent Storage:** In **Storage → Add**, configure:

   | Field | Value |
   |---|---|
   | Type | Host Path (Path that already exists on the system) |
   | Read Only | Unchecked |
   | Mount Path | `/var/lib/mysql` |
   | Enable ACL | Unchecked |
   | Host Path | Select your database dataset, for example `/mnt/<SSD_POOL>/DB/MariaDB` |

   The host path is local SSD-backed storage on TrueNAS; it is not an NFS mount on `cf_vm`. The application's **Enable ACL** option is separate from the dataset's existing permissions.
10. **Optionally Set Resource Limits:** In **Resources Configuration**, enable **Enable Resource Limits** if you want a resource cap. Choose limits for your workload, for example **CPUs: 2** and **Memory (in MB): 4096**, as used in this deployment. Leave GPU passthrough unchecked.
11. **Deploy and Check Startup:** Review the form and install the application. Select it in **Apps** and inspect its status and container logs. Expect MariaDB to remain running and report that it is ready for connections, without initialization or storage-permission errors.
12. **Verify the Database:** Open the MariaDB container's **Shell** from its application page. Run:

   ```bash
   mariadb -u root -p
   ```

   Enter the root password at the prompt, then run:

   ```sql
   SELECT VERSION();
   SHOW DATABASES;
   SELECT @@GLOBAL.tx_isolation;
   ```

   Expect your chosen Nextcloud database to appear and the isolation value to be `READ-COMMITTED`. Record the server version for compatibility checks, then enter `exit` to close the client. Test the application account separately:

   ```bash
   mariadb -u '<NEXTCLOUD_DB_USER>' -p '<NEXTCLOUD_DB_NAME>' -e 'SELECT DATABASE();'
   ```

   Replace the placeholders with the values from Step 7 and enter that user's password when prompted. Expect the chosen database name.

Return to [Nextcloud configuration on CF VM](../cf_vm/README.md#51-nextcloud) to configure its connection and check application access.

#### 3.1.2 Mass-Storage Dataset

Nextcloud's application files use one mass-storage dataset, mounted at `/mnt/truenas/nextcloud` on `cf_vm` and mapped to `/var/www/html` in the container. MariaDB files remain in the separate SSD-backed database dataset.

1. **Identify the Storage Account:** In the **TrueNAS shell**, run:

   ```bash
   id www-data
   ```

   Record the account's UID and primary GID separately. In the **TrueNAS web interface → Credentials → Users**, locate `www-data`; this account is used for filesystem ownership.
2. **Create the Dataset:** In **TrueNAS → Datasets**, select the existing mass-storage parent for this VM, for example `<MASS_STORAGE_POOL>/cf_vm`, and click **Add Dataset**. Enter your desired **Name**, for example `Nextcloud`. Select **Generic** as **Dataset Preset** for the Unix permissions below.
3. **Set Dataset Properties:** In **Advanced Options**, choose properties for your storage needs. This setup uses **Sync: Standard**, **Compression: Inherit (LZ4)**, **Atime: Off**, **Deduplication: Off**, and case-sensitive names. Save the dataset.
4. **Assign Ownership and Permissions:** Select the dataset and open **Permissions → Edit**. Set **User** and **Group** to `www-data`, select **Apply User** and **Apply Group**, and give both **User** and **Group** read, write and execute. Give **Other** no permissions. Save. This is Unix mode **770**; apply these settings to the new dataset without recursively changing existing application files.
5. **Optionally Limit Storage:** In **Dataset Space Management → Edit**, choose a quota if you want to cap storage usage, or leave it unset. Dataset quotas and user/group quotas are separate settings.
6. **Verify the Dataset:** Reopen it and confirm its path, `www-data:www-data` ownership, Unix mode **770**, properties and any quota you configured.

Create the [Nextcloud NFS share](#313-nfs-share), then continue with [CF VM mounting](../cf_vm/README.md#42-mounting-nfs-shares-in-the-debian-vm). The example TrueNAS path `/mnt/<MASS_STORAGE_POOL>/cf_vm/Nextcloud` becomes `/mnt/truenas/nextcloud` on the VM; [Nextcloud Compose](../cf_vm/docker-compose.yml) maps that VM path to `/var/www/html`.

#### 3.1.3 NFS Share

1. **Add the Share:** In **TrueNAS → Shares → NFS**, click **Add**. Select the Nextcloud dataset you created as **Path**, for example `/mnt/<MASS_STORAGE_POOL>/cf_vm/Nextcloud`.
2. **Configure Access:** Leave **Description** empty, check **Enabled**, and leave **Read Only** unchecked. Set **Maproot User** and **Maproot Group** to `www-data`. Leave **Mapall User** and **Mapall Group** unset, and leave **Security** without an explicit selection.
3. **Restrict the Client:** Under **Networks → Add**, enter `<CF_VM_IP>` with prefix length **32**. Replace the placeholder with the CF VM's LAN IPv4 address; `/32` selects that single client. Maproot maps client root requests to `www-data`; it does not map every application's user as Mapall would.
4. **Verify the Share:** Save, reopen the share, and confirm its dataset path, enabled and writable state, `<CF_VM_IP>/32` client entry, `www-data:www-data` Maproot and unset Mapall.

Continue with [CF VM NFS mounting](../cf_vm/README.md#42-mounting-nfs-shares-in-the-debian-vm), mounting this export at `/mnt/truenas/nextcloud`. Verify the export source before [deploying Nextcloud](../cf_vm/README.md#43-deploying-the-docker-stack).

### 3.2 Paperless-ngx

Paperless connects to the same TrueNAS MariaDB application as Nextcloud. Its database files remain in the shared MariaDB SSD dataset. Paperless uses one mass-storage dataset mounted at `/mnt/truenas/paperless` on `cf_vm`. Its `data` and `media` directories live within that dataset. Export and consume directories remain local to the VM in the [CF stack configuration](../cf_vm/README.md#43-deploying-the-docker-stack).

#### 3.2.1 Mass-Storage Dataset

1. **Create the Storage User:** In **TrueNAS → Credentials → Users → Add**, enter your desired **Full Name**, for example `Paperless`, and **Username**, for example `paperless`. Select **Create New Primary Group**, choose an available UID, and save. This account supplies filesystem ownership and numeric IDs for Paperless.
2. **Record the IDs:** In the **TrueNAS shell**, run:

   ```bash
   id paperless
   ```

   Substitute your chosen username. Record its UID as `<PAPERLESS_UID>` and its primary GID as `<PAPERLESS_GID>`; do not assume they are equal. Use these as stack `PAPERLESS_UID` and `PAPERLESS_GID`, which Compose passes as `USERMAP_UID` and `USERMAP_GID`.
3. **Create the Dataset:** In **TrueNAS → Datasets**, select the existing mass-storage parent for this VM, for example `<MASS_STORAGE_POOL>/cf_vm`, and click **Add Dataset**. Enter your desired **Name**, for example `Paperless`, and select **Generic** as **Dataset Preset**.
4. **Set Dataset Properties:** In **Advanced Options**, choose properties for your storage needs. This setup uses **Sync: Standard**, **Compression: Inherit (LZ4)**, **Atime: Off**, **Deduplication: Off**, and case-sensitive names. Save.
5. **Assign Ownership and Permissions:** Select the dataset and open **Permissions → Edit**. Set **User** and **Group** to the storage account and group you created (`paperless` in these examples). Select **Apply User** and **Apply Group**. Give **User** read, write and execute; **Group** read and execute; and **Other** no permissions. Save. This is Unix mode **750**, applied to the new dataset without recursively modifying existing files.
6. **Optionally Limit Storage:** In **Dataset Space Management → Edit**, choose a quota to cap storage usage if desired, or leave it unset. User/group quotas are separate settings.
7. **Verify the Dataset:** Reopen it and confirm its path, ownership by the storage user/group, Unix mode **750**, properties and any configured quota.

Create the [Paperless NFS share](#322-nfs-share) and continue with [CF VM mounting and directory preparation](../cf_vm/README.md#42-mounting-nfs-shares-in-the-debian-vm). The example export path `/mnt/<MASS_STORAGE_POOL>/cf_vm/Paperless` is mounted at `/mnt/truenas/paperless`. Create ordinary `data` and `media` directories inside the VM mount and assign them the recorded IDs before starting Paperless. The [CF guide](../cf_vm/README.md#52-paperless-ngx) retains database connection and application settings.


#### 3.2.2 NFS Share

1. **Add the Share:** In **TrueNAS → Shares → NFS**, click **Add**. Select the Paperless dataset you created as **Path**, for example `/mnt/<MASS_STORAGE_POOL>/cf_vm/Paperless`. Export the whole application dataset so the VM can access its `data` and `media` directories through one mount.
2. **Configure Access:** Leave **Description** empty, check **Enabled**, and leave **Read Only** unchecked. Set **Maproot User** and **Maproot Group** to the storage account and group you created (`paperless` in these examples). Leave **Mapall User** and **Mapall Group** unset, and leave **Security** without an explicit selection.
3. **Restrict the Client:** Under **Networks → Add**, enter `<CF_VM_IP>` with prefix length **32**, using the CF VM's LAN IPv4 address. Maproot maps client root requests to the Paperless storage account; other users still need the appropriate numeric ownership and permissions.
4. **Verify the Share:** Save, reopen it, and confirm the whole Paperless dataset path, enabled and writable state, `<CF_VM_IP>/32` client entry, storage-account Maproot and unset Mapall.

Continue with [CF VM NFS mounting and Paperless directory preparation](../cf_vm/README.md#42-mounting-nfs-shares-in-the-debian-vm). Mount the single export at `/mnt/truenas/paperless`, then create `data` and `media` inside that mount. Both directories should resolve to this same NFS source; configure stack `PAPERLESS_UID` and `PAPERLESS_GID` with the IDs recorded during dataset setup.


#### 3.2.3 MariaDB Connection

Reuse the [MariaDB dataset and application deployment](#311-mariadb-dataset-and-deployment); do not deploy a second server or export its database files through NFS. Configure the existing Paperless database and account in the [CF VM stack environment](../cf_vm/README.md#52-paperless-ngx):

| Stack variable | Value source | Container variable |
|---|---|---|
| `DB_HOST` | `<TRUENAS_IP>`, the same MariaDB server used by Nextcloud | `PAPERLESS_DBHOST` |
| `DB_PORT` | `<PUBLISHED_MARIADB_PORT>`, the MariaDB application's host port | `PAPERLESS_DBPORT` |
| `DB_NAME` | Database name configured for Paperless | `PAPERLESS_DBNAME` |
| `DB_USER` | Database account configured for Paperless | `PAPERLESS_DBUSER` |
| `DB_PASS` | Password for that account | `PAPERLESS_DBPASS` |

Compose sets `PAPERLESS_DBENGINE=mariadb`. Use Paperless's own database name and database user, which differ from Nextcloud's. Obtain its account password from the Paperless database configuration. Return to [CF stack deployment](../cf_vm/README.md#43-deploying-the-docker-stack) after setting these values.
