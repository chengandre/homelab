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
4. [SMB and Time Machine](#4-smb-and-time-machine)
   * [Datasets and Accounts](#41-datasets-and-accounts)
   * [SMB Shares](#42-smb-shares)
   * [macOS Time Machine Setup](#43-macos-time-machine-setup)
   * [Snapshot Tasks](#44-snapshot-tasks)

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
3. **Create the Dataset:** In **Datasets**, select the dataset for this VM, for example `<MASS_STORAGE_POOL>/ts_vm`, and click **Add Dataset**. Enter your desired **Name**, for example `Immich`. Select **Generic** as **Dataset Preset** for this Unix-permissions dataset. See [TrueNAS dataset creation](https://www.truenas.com/docs/scale/24.10/scaletutorials/datasets/datasetsscale/).
4. **Review Dataset Properties:** Leave the inherited advanced dataset properties unchanged and save the dataset. Its example path is `<MASS_STORAGE_POOL>/ts_vm/Immich`.
5. **Assign Ownership:** Select the new dataset and click **Edit** in **Permissions**. In the Unix permissions editor, set **User** and **Group** to the storage account and group you created (`immich` in these examples). Select **Apply User** and **Apply Group**.
6. **Set Permissions:** Give **User** read, write, and execute; **Group** read and execute; and **Other** no permissions. Save. This is Unix mode **750**. These steps configure the new dataset; recursively changing existing application files is a separate operation. See the [TrueNAS permissions editor](https://www.truenas.com/docs/scale/24.10/scaleuireference/datasets/editaclscreens/).
7. **Optionally Limit Storage:** To cap storage usage, open **Dataset Space Management → Edit** and choose a dataset quota, for example **1 TiB**, including descendants. You can leave the dataset without a quota. User and group quotas are separate settings.
8. **Verify the Dataset:** Reopen the dataset and confirm its path, ownership by your storage user and group, Unix permissions, properties, and any quota you configured before creating the NFS share.

#### 2.1.2 NFS Share

1. **Add the Share:** In the **TrueNAS web interface → Shares → NFS**, click **Add** and select the dataset you created as **Path**, for example `/mnt/<MASS_STORAGE_POOL>/ts_vm/Immich`.
2. **Keep the General Defaults:** Leave **Description** empty and keep **Enabled** selected. Leave **Hosts** empty.
3. **Restrict the Client:** Under **Networks**, click **Add** and enter `<TS_VM_IP>` with prefix length **32**. Use the TS VM's LAN address; the `/32` entry selects that single IPv4 address.
4. **Configure Advanced Options:** Click **Advanced Options**. Leave **Read Only** unchecked. Set **Maproot User** and **Maproot Group** to your storage account and group (`immich` in these examples). Leave **Mapall User**, **Mapall Group**, and **Security** unset.
5. **Verify the Share:** Save, reopen the share, and confirm the export path, enabled state, writable setting, client entry, and user/group mappings.

Continue with [TS VM storage mounting](../ts_vm/README.md#41-preparing-and-mounting-truenas-storage), using this export path. TrueNAS paths, VM mount points, and container paths are distinct.

The single Immich export contains both the library and model-cache data. Bind-mount their respective directories into the containers from the mounted dataset.

#### 2.1.3 PostgreSQL Dataset and Deployment

The TrueNAS PostgreSQL application uses a database dataset on the SSD pool, mounted locally into the container. It is separate from the VM's NFS storage.

1. **Create the Database Dataset:** In the **TrueNAS web interface → Datasets**, select your SSD pool's database parent dataset (`DB` in this example) and click **Add Dataset**. Enter your desired **Name**, for example `Postgresql`, and save the dataset.
2. **Review Dataset Properties:** Leave the inherited advanced dataset properties unchanged and save the dataset.
3. **Open the Custom App Wizard:** In the **TrueNAS web interface → Apps → Discover Apps → Custom App**, enter your desired **Application Name**, for example `postgresql`. Use the guided form shown as **Install iX App**; an existing application's edit form is titled **Edit iX App**. See [TrueNAS custom app installation](https://apps.truenas.com/managing-apps/installing-custom-apps/).
4. **Configure the Image:** In **Image Configuration**, enter:

   | Field | Value |
   |---|---|
   | Repository | `ghcr.io/immich-app/postgres` |
   | Tag used in this deployment | `14-vectorchord0.3.0-pgvectors0.2.0` |
   | Pull Policy | Pull the image if it is not already present on the host |

   Use a database image compatible with your Immich release. The tag above records this deployment; check your release's database requirements before choosing another tag.
5. **Configure the Container:** In **Container Configuration**, choose your **Timezone** and set **Restart Policy** to **Unless Stopped**. Leave **Hostname** empty, add no **Entrypoint** or **Command** overrides, leave **Disable Builtin Healthcheck**, **TTY**, and **Stdin** unchecked, and add no devices.
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

   The mount path is the container destination for the configured PostgreSQL 14 image. The host path is local to TrueNAS and belongs on the SSD pool. **Enable ACL** here is an application mount option; leave it unchecked unless you have a separate reason to change the dataset permissions during app installation.
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
3. **Create the Dataset:** In **Datasets**, select the dataset for this VM, for example `<MASS_STORAGE_POOL>/ts_vm`, and click **Add Dataset**. Enter your desired **Name**, for example `Vaultwarden`. Select **Generic** as **Dataset Preset** for this Unix-permissions dataset. See [TrueNAS dataset creation](https://www.truenas.com/docs/scale/24.10/scaletutorials/datasets/datasetsscale/).
4. **Review Dataset Properties:** Leave the inherited advanced dataset properties unchanged and save the dataset. Its example path is `<MASS_STORAGE_POOL>/ts_vm/Vaultwarden`.
5. **Assign Ownership:** Select the new dataset and click **Edit** in **Permissions**. In the Unix permissions editor, set **User** and **Group** to the storage account and group you created (`vaultwar` in these examples). Select **Apply User** and **Apply Group**.
6. **Set Permissions:** Give **User** read, write, and execute; **Group** read and execute; and **Other** no permissions. Save. This is Unix mode **750**. These steps configure the new dataset; recursively changing existing application files is a separate operation. See the [TrueNAS permissions editor](https://www.truenas.com/docs/scale/24.10/scaleuireference/datasets/editaclscreens/).
7. **Optionally Limit Storage:** To cap storage usage, open **Dataset Space Management → Edit** and choose a dataset quota, for example **5 GiB**, including descendants. You can leave the dataset without a quota. User and group quotas are separate settings.
8. **Verify the Dataset:** Reopen the dataset and confirm its path, ownership by your storage user and group, Unix permissions, properties, and any quota you configured before creating the NFS share.

#### 2.2.2 NFS Share

1. **Add the Share:** In the **TrueNAS web interface → Shares → NFS**, click **Add** and select the dataset you created as **Path**, for example `/mnt/<MASS_STORAGE_POOL>/ts_vm/Vaultwarden`.
2. **Keep the General Defaults:** Leave **Description** empty and keep **Enabled** selected. Leave **Hosts** empty.
3. **Restrict the Client:** Under **Networks**, click **Add** and enter `<TS_VM_IP>` with prefix length **32**. Use the TS VM's LAN address; the `/32` entry selects that single IPv4 address.
4. **Configure Advanced Options:** Click **Advanced Options**. Leave **Read Only** unchecked. Set **Maproot User** and **Maproot Group** to your storage account and group (`vaultwar` in these examples). Leave **Mapall User**, **Mapall Group**, and **Security** unset.
5. **Verify the Share:** Save, reopen the share, and confirm the export path, enabled state, writable setting, client entry, and user/group mappings.

Continue with [TS VM storage mounting](../ts_vm/README.md#41-preparing-and-mounting-truenas-storage), using this export path. TrueNAS paths, VM mount points, and container paths are distinct.

After mounting storage, continue with [Vaultwarden configuration on TS VM](../ts_vm/README.md#52-vaultwarden).

## 3. CF VM

TrueNAS provides NFS-backed application storage and database applications for services on `cf_vm`. Complete the relevant database setup before deploying the [CF VM Docker stack](../cf_vm/README.md#43-deploying-the-docker-stack).

### 3.1 Nextcloud

Nextcloud runs on `cf_vm` and connects to MariaDB on TrueNAS. Its application files use the VM's mounted storage; MariaDB's database files remain local to the SSD pool on TrueNAS.

#### 3.1.1 MariaDB Dataset and Deployment

One MariaDB application on TrueNAS serves both Nextcloud and Paperless on `cf_vm`, each with its own database name and database user. Deploy the dataset and application once; Paperless reuses this server through its [database connection settings](#323-mariadb-connection). The initialization variables below create one application database/account on a fresh server, not both applications' database configurations.

1. **Create the Database Dataset:** In the **TrueNAS web interface → Datasets**, select your SSD pool's database parent dataset, for example `<SSD_POOL>/DB`, and click **Add Dataset**. Enter your desired **Name**, for example `MariaDB`, and save the dataset. Its example host path is `/mnt/<SSD_POOL>/DB/MariaDB`.
2. **Review Dataset Properties:** Leave the inherited advanced dataset properties unchanged and save the dataset.
3. **Open the Custom App Wizard:** In **Apps → Discover Apps → Custom App**, enter your desired **Application Name**, for example `mariadb`.
4. **Configure the Image:** In **Image Configuration**, enter:

   | Field | Value |
   |---|---|
   | Repository | `mariadb` |
   | Tag used in this deployment | `lts` |
   | Pull Policy | Pull the image if it is not already present on the host |

   The `lts` tag is the configured image tag, rather than a confirmed running server version. Choose a MariaDB version supported by your Nextcloud release.
5. **Configure the Container:** In **Container Configuration**, choose your local **Timezone** from the dropdown. Leave **Hostname** empty and add no **Entrypoint** override. Keep the remaining container options, security context, custom DNS, portal, and label settings at their wizard defaults. Under **Command → Add**, enter one argument:

   ```text
   --transaction-isolation=READ-COMMITTED
   ```

   This sets the database's transaction isolation for Nextcloud. See [Nextcloud's database configuration guidance](https://docs.nextcloud.com/server/stable/admin_manual/configuration_database/linux_database_configuration.html).
6. **Add Initialization Variables:** Add one environment-variable entry for each of the following:

   | Variable | Value to enter | Purpose |
   |---|---|---|
   | `MYSQL_ROOT_PASSWORD` | `<MARIADB_ROOT_PASSWORD>` | Choose a strong password for the MariaDB root account |
   | `MYSQL_PASSWORD` | `<NEXTCLOUD_DB_PASSWORD>` | Choose the application database user's password |
   | `MYSQL_DATABASE` | `<NEXTCLOUD_DB_NAME>` | Choose a database name, for example `nextcloud` |
   | `MYSQL_USER` | `<NEXTCLOUD_DB_USER>` | Choose an application database username, for example `nextcloud` |

   Enter your chosen values in place of the placeholders. `MYSQL_USER` creates a database account with access to `MYSQL_DATABASE`; it is separate from the TrueNAS dataset owner. Use this application account for Nextcloud. The `MYSQL_*` initialization variables are supported by the MariaDB image and configure a fresh database; changing them does not reset an existing database's users or passwords. See the [MariaDB image environment reference](https://mariadb.com/docs/server/server-management/install-and-upgrade-mariadb/installing-mariadb/binary-packages/automated-mariadb-deployment-and-administration/docker-and-mariadb/mariadb-server-docker-official-image-environment-variables).
7. **Publish the Database Port:** In **Network Configuration**, leave **Host Network** unchecked. Under **Ports → Add**, enter:

   | Field | Value |
   |---|---|
   | Container Port | `3306` |
   | Host Port | Choose an available port, for example `3306` |
   | Protocol | `TCP` |

   Record the host port as `<PUBLISHED_MARIADB_PORT>`. Nextcloud connects to `<TRUENAS_IP>` at this port.
8. **Map Persistent Storage:** In **Storage → Add**, configure:

   | Field | Value |
   |---|---|
   | Type | Host Path (Path that already exists on the system) |
   | Read Only | Unchecked |
   | Mount Path | `/var/lib/mysql` |
   | Enable ACL | Unchecked |
   | Host Path | Select your database dataset, for example `/mnt/<SSD_POOL>/DB/MariaDB` |

   The host path is local SSD-backed storage on TrueNAS; it is not an NFS mount on `cf_vm`. The application's **Enable ACL** option is separate from the dataset's existing permissions.
9. **Optionally Set Resource Limits:** In **Resources Configuration**, enable **Enable Resource Limits** if you want a resource cap. Choose limits for your workload, for example **CPUs: 2** and **Memory (in MB): 4096**, as used in this deployment. Leave GPU passthrough unchecked.
10. **Deploy and Check Startup:** Review the form and install the application. Select it in **Apps** and inspect its status and container logs. Expect MariaDB to remain running and report that it is ready for connections, without initialization or storage-permission errors.
11. **Verify the Database:** Open the MariaDB container's **Shell** from its application page. Run:

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
3. **Review Dataset Properties:** Leave the inherited advanced dataset properties unchanged and save the dataset.
4. **Assign Ownership and Permissions:** Select the dataset and open **Permissions → Edit**. Set **User** and **Group** to `www-data`, select **Apply User** and **Apply Group**, and give both **User** and **Group** read, write and execute. Give **Other** no permissions. Save. This is Unix mode **770**; apply these settings to the new dataset without recursively changing existing application files.
5. **Optionally Limit Storage:** In **Dataset Space Management → Edit**, choose a quota if you want to cap storage usage, or leave it unset. Dataset quotas and user/group quotas are separate settings.
6. **Verify the Dataset:** Reopen it and confirm its path, `www-data:www-data` ownership, Unix mode **770**, properties and any quota you configured.

Create the [Nextcloud NFS share](#313-nfs-share), then continue with [CF VM mounting](../cf_vm/README.md#42-mounting-nfs-shares-in-the-debian-vm). The example TrueNAS path `/mnt/<MASS_STORAGE_POOL>/cf_vm/Nextcloud` becomes `/mnt/truenas/nextcloud` on the VM; [Nextcloud Compose](../cf_vm/docker-compose.yml) maps that VM path to `/var/www/html`.

#### 3.1.3 NFS Share

1. **Add the Share:** In **TrueNAS → Shares → NFS**, click **Add**. Select the Nextcloud dataset you created as **Path**, for example `/mnt/<MASS_STORAGE_POOL>/cf_vm/Nextcloud`.
2. **Keep the General Defaults:** Leave **Description** empty and keep **Enabled** selected. Leave **Hosts** empty.
3. **Restrict the Client:** Under **Networks**, click **Add** and enter `<CF_VM_IP>` with prefix length **32**. Replace the placeholder with the CF VM's LAN IPv4 address; `/32` selects that single client.
4. **Configure Advanced Options:** Click **Advanced Options**. Leave **Read Only** unchecked. Set **Maproot User** and **Maproot Group** to `www-data`. Leave **Mapall User**, **Mapall Group**, and **Security** unset. Maproot maps client root requests to `www-data`; it does not map every application's user as Mapall would.
5. **Verify the Share:** Save, reopen the share, and confirm its dataset path, enabled and writable state, `<CF_VM_IP>/32` client entry, `www-data:www-data` Maproot and unset Mapall.

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
4. **Review Dataset Properties:** Leave the inherited advanced dataset properties unchanged and save the dataset.
5. **Assign Ownership and Permissions:** Select the dataset and open **Permissions → Edit**. Set **User** and **Group** to the storage account and group you created (`paperless` in these examples). Select **Apply User** and **Apply Group**. Give **User** read, write and execute; **Group** read and execute; and **Other** no permissions. Save. This is Unix mode **750**, applied to the new dataset without recursively modifying existing files.
6. **Optionally Limit Storage:** In **Dataset Space Management → Edit**, choose a quota to cap storage usage if desired, or leave it unset. User/group quotas are separate settings.
7. **Verify the Dataset:** Reopen it and confirm its path, ownership by the storage user/group, Unix mode **750**, properties and any configured quota.

Create the [Paperless NFS share](#322-nfs-share) and continue with [CF VM mounting and directory preparation](../cf_vm/README.md#42-mounting-nfs-shares-in-the-debian-vm). The example export path `/mnt/<MASS_STORAGE_POOL>/cf_vm/Paperless` is mounted at `/mnt/truenas/paperless`. Create ordinary `data` and `media` directories inside the VM mount and assign them the recorded IDs before starting Paperless. The [CF guide](../cf_vm/README.md#52-paperless-ngx) retains database connection and application settings.


#### 3.2.2 NFS Share

1. **Add the Share:** In **TrueNAS → Shares → NFS**, click **Add**. Select the Paperless dataset you created as **Path**, for example `/mnt/<MASS_STORAGE_POOL>/cf_vm/Paperless`. Export the whole application dataset so the VM can access its `data` and `media` directories through one mount.
2. **Keep the General Defaults:** Leave **Description** empty and keep **Enabled** selected. Leave **Hosts** empty.
3. **Restrict the Client:** Under **Networks**, click **Add** and enter `<CF_VM_IP>` with prefix length **32**, using the CF VM's LAN IPv4 address.
4. **Configure Advanced Options:** Click **Advanced Options**. Leave **Read Only** unchecked. Set **Maproot User** and **Maproot Group** to the storage account and group you created (`paperless` in these examples). Leave **Mapall User**, **Mapall Group**, and **Security** unset. Maproot maps client root requests to the Paperless storage account; other users still need the appropriate numeric ownership and permissions.
5. **Verify the Share:** Save, reopen it, and confirm the whole Paperless dataset path, enabled and writable state, `<CF_VM_IP>/32` client entry, storage-account Maproot and unset Mapall.

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

## 4. SMB and Time Machine

TrueNAS stores Time Machine backups in one parent dataset with one child dataset and SMB share per Mac. The child dataset and SMB account use the same username for each Mac, and each child has its own dataset quota. The Macs reach TrueNAS over the existing Tailscale connection; this section covers the TrueNAS storage and SMB configuration plus the macOS destination setup.

### 4.1 Datasets and Accounts

Create one account, group, child dataset, and quota for each Mac. The examples below use `<MAC_USERNAME>` for one Mac. If you have multiple Macs, repeat the account, child-dataset, quota, SMB-share, and macOS setup steps for each Mac with a different matching username.

1. **Create the Parent Dataset:** In **TrueNAS → Datasets**, select the pool where Time Machine backups belong, for example `<MASS_STORAGE_POOL>`, and click **Add Dataset**. Enter `TimeMachine` as the parent dataset name. Use the dataset properties appropriate for the pool. Because Time Machine is designed to use available storage for historical backups, consider setting a parent dataset quota if you want to reserve space for other consumers.
2. **Create the Mac User and Group:** In **TrueNAS → Credentials → Users → Add**, create a user whose **Username** matches the macOS account that will authenticate to SMB, for example `<MAC_USERNAME>`. Create a dedicated primary group for that user, choose an available UID, and set an SMB password. These accounts are for SMB authentication and dataset ownership; do not publish their passwords. For another Mac, create another dedicated user and group matching that Mac's account.
3. **Create the Child Dataset:** In **TrueNAS → Datasets**, select `<MASS_STORAGE_POOL>/TimeMachine` and click **Add Dataset**. Set **Name** to `<MAC_USERNAME>`, producing the example path `/mnt/<MASS_STORAGE_POOL>/TimeMachine/<MAC_USERNAME>`. Create one additional child dataset for each additional Mac, using that Mac's matching username as the dataset name.
4. **Set Dataset Ownership:** Open the child dataset's **Permissions → Edit ACL**. Set **Owner** to the matching Mac user and **Owner Group** to its dedicated group. If creating the dataset from scratch, apply the owner and group to the new dataset.
5. **Set Dataset ACL Entries:** For each child dataset, configure the access entries as follows:

   | Entry | Permissions |
   |---|---|
   | User Obj — matching Mac user | Read, Write, Execute |
   | Group Obj — dedicated group | Read, Write, Execute |
   | Other | Read |

   Configure the corresponding default entries so the matching user and group have **Read, Write, Execute**, while **Other** has **None**. Do not apply permissions recursively to existing backup data unless you intentionally need to repair it.
6. **Set Dataset Quotas:** Open **Dataset Space Management → Edit** for each child and configure an optional quota appropriate for that Mac. Per-Mac quotas prevent one computer's history from consuming all space available to the other datasets. If you set both parent and child quotas, ensure the child limits fit within the parent limit and leave room for normal ZFS operation. User and group quotas are separate settings.

### 4.2 SMB Shares

Create one SMB share for each child dataset. Repeat these steps for every additional Mac, using its matching child-dataset path and share name.

1. **Add the Share:** In **TrueNAS → Shares → Windows (SMB) Shares**, click **Add**. Set **Path** to `/mnt/<MASS_STORAGE_POOL>/TimeMachine/<MAC_USERNAME>` and **Name** to `<MAC_USERNAME>`.
2. **Select the Purpose:** Set **Purpose** to **Multi-user time machine**. Leave **Description** empty and keep **Enabled** selected.
3. **Leave the Access Defaults:** Keep **Enable ACL** selected, **Export Read Only** unchecked, **Browsable to Network Clients** selected, and **Allow Guest Access** and **Access Based Share Enumeration** unchecked. Leave **Hosts Allow** and **Hosts Deny** empty unless you intentionally want an additional host restriction; Tailscale access is handled by the existing network configuration.
4. **Enable Time Machine:** Under **Other Options**, confirm **Time Machine** is enabled. Leave **Time Machine Quota** blank at its default unless you want a separate SMB-share quota; the optional dataset quotas in Section 4.1 are the primary storage limits described here. Leave **Legacy AFP Compatibility** unchecked.
5. **Change Only the Required Advanced Option:** Enable **Use Apple-style Character Encoding**. Leave the other advanced options at their defaults: **Audit Logging** disabled, **Use as Home Share** unchecked, **Enable Shadow Copies** enabled, **Enable Alternate Data Streams** enabled, **Enable SMB2/3 Durable Handles** enabled, and **Enable FSRVP** unchecked. Keep **Path Suffix** as `%U` and leave **Additional Parameters String** at its default value, `zfs_core:zfs_auto_create=true`.
6. **Save the Share:** Save the share. For each additional Mac, repeat Steps 1–5 with its child dataset path and share name. Each Mac must use its own SMB account and share.

### 4.3 macOS Time Machine Setup

Repeat these steps on each Mac while it is connected to the tailnet.

1. **Open Time Machine Settings:** Open **System Settings → General → Time Machine** and click **Add Backup Disk** or **Add Backup Disk…**, depending on the macOS version.
2. **Select the Share:** Choose the SMB share matching that Mac's username, for example `<MAC_USERNAME>`.
3. **Authenticate:** When prompted, choose the registered-user option and enter the matching TrueNAS SMB username and password. Enable **Remember this password in my keychain** if desired.
4. **Choose the Backup Options:** Confirm the selected destination and configure the Mac's preferred backup schedule and exclusions. macOS may offer an option to encrypt the backup; choose according to the owner's backup policy. This guide does not claim whether the deployed backups are encrypted.
5. **Repeat for Additional Macs:** Configure each additional Mac with its matching TrueNAS username and SMB share. Do not point multiple Macs at the same child dataset.

### 4.4 Snapshot Tasks

Create a snapshot task for each Mac's Time Machine child dataset. Snapshots provide a separate ZFS recovery point for the backup dataset; they do not replace the Mac's Time Machine history or a separate backup of the TrueNAS system.

1. **Open Snapshot Tasks:** In **TrueNAS → Datasets**, select the child dataset for the Mac. Open **Data Protection → Manage Snapshot Tasks** and choose the option to add a task.
2. **Select the Dataset:** Set **Dataset** to the selected Mac-specific Time Machine dataset. Repeat this procedure for each additional Mac's child dataset.
3. **Set the Snapshot Lifetime:** Set **Snapshot Lifetime** to `1` and **Unit** to **Week**. This automatically expires snapshots after one week.
4. **Keep the Dataset Scope:** Leave **Exclude** empty and **Recursive** unchecked so the task snapshots only the selected child dataset. Do not enable recursive snapshots unless you intentionally want the task to include descendant datasets.
5. **Keep the Naming Default:** Leave **Naming Schema** at its default value, for example `auto-%Y-%m-%d_%H-%M`.
6. **Set the Schedule:** Set **Schedule** to **Daily at 00:00 (12:00 AM)**. Leave **Allow Taking Empty Snapshots** unchecked and keep **Enabled** selected.
7. **Save the Task:** Save the snapshot task. Repeat Steps 1–6 for each Mac-specific child dataset.
