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
     * [Persistent Dataset](#221-persistent-dataset)
     * [NFS Share](#222-nfs-share)
3. [CF VM](#3-cf-vm)
   * [Nextcloud](#31-nextcloud)
     * [MariaDB Dataset and Deployment](#311-mariadb-dataset-and-deployment)

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

1. **Create the Storage User:** In the **TrueNAS web interface → Credentials → Users → Add**, enter your desired **Full Name**, for example `Immich`, and **Username**, for example `immich`. Select **Create New Primary Group** to create a group matching your chosen username, then save the account. Choose an available UID; authentication and home-directory options are described in the [TrueNAS 24.10 user guide](https://www.truenas.com/docs/scale/24.10/scaletutorials/credentials/managelocalusersscale/).
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
2. **Set Access Options:** Leave **Description** empty, check **Enabled**, and leave **Read Only** unchecked. Set **Maproot User** and **Maproot Group** to your storage account and group (`immich` in these examples). Leave **Mapall User** and **Mapall Group** unset. The deployed share has no explicit selection shown in **Security**.
3. **Restrict the Client:** In **Networks**, add `<TS_VM_IP>` with prefix length **32**. Use the TS VM's LAN address; the `/32` entry selects that single IPv4 address. The deployed share uses Maproot, rather than Mapall.
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
5. **Configure the Container:** In **Container Configuration**, leave **Hostname** empty and add no **Entrypoint** or **Command** overrides. Choose your **Timezone**, for example **Europe/Lisbon**, and set **Restart Policy** to **Unless Stopped**. Leave **Disable Builtin Healthcheck**, **TTY**, and **Stdin** unchecked, and add no devices.
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

#### 2.2.1 Persistent Dataset

1. **Create the Storage User:** In the **TrueNAS web interface → Credentials → Users → Add**, enter your desired **Full Name**, for example `Vaultwarden`, and **Username**, for example `vaultwar`. Select **Create New Primary Group** to create a group matching your chosen username, then save the account. Choose an available UID; authentication and home-directory options are described in the [TrueNAS 24.10 user guide](https://www.truenas.com/docs/scale/24.10/scaletutorials/credentials/managelocalusersscale/).
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
2. **Set Access Options:** Leave **Description** empty, check **Enabled**, and leave **Read Only** unchecked. Set **Maproot User** and **Maproot Group** to your storage account and group (`vaultwar` in these examples). Leave **Mapall User** and **Mapall Group** unset. The deployed share has no explicit selection shown in **Security**.
3. **Restrict the Client:** In **Networks**, add `<TS_VM_IP>` with prefix length **32**. Use the TS VM's LAN address; the `/32` entry selects that single IPv4 address. The deployed share uses Maproot, rather than Mapall.
4. **Verify the Share:** Save, reopen the share, and confirm the export path, enabled state, writable setting, client entry, and user/group mappings.

Continue with [TS VM storage mounting](../ts_vm/README.md#41-preparing-and-mounting-truenas-storage), using this export path. TrueNAS paths, VM mount points, and container paths are distinct.

After mounting storage, continue with [Vaultwarden configuration on TS VM](../ts_vm/README.md#52-vaultwarden).

## 3. CF VM

Database applications on TrueNAS provide persistent database storage for services on `cf_vm`. Complete the relevant database setup before deploying the [CF VM Docker stack](../cf_vm/README.md#43-deploying-the-docker-stack).

### 3.1 Nextcloud

Nextcloud runs on `cf_vm` and connects to MariaDB on TrueNAS. Its application files use the VM's mounted storage; MariaDB's database files remain local to the SSD pool on TrueNAS.

#### 3.1.1 MariaDB Dataset and Deployment

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
