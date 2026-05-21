# Replicate Database on Google Cloud SQL

*Author*: Timm Nawrocki, Alaska Center for Conservation Science

*Last Updated*: 2022-10-18

*Description*: Instructions to export the schema and data of one database and copy to another database.

## 1. Configure project
These instructions assume that project already exists called "accs-postgresql", and instance has been configured called "target-instance", and includes a database to be copied called "target_database". The target-instance must be running while the operations below are completed.

### Create a storage bucket for the project
Create a new storage bucket if one does not already exist for use. Instructions to [create storage buckets](https://cloud.google.com/storage/docs/creating-buckets) are available through the Google Cloud reference documentation.

The storage bucket in this example is named "database_export". Find the instance service account address using the following command:

```
gcloud config set project accs-postgresql
gcloud sql instances describe target-instance
```

If the target instance is accessible, then the result will show information on the target-instance. Copy the service account address, which is unique to each instance, and use it to grant the service account object creation permission for the storage bucket.

```
gsutil iam ch serviceAccount:p196247013763-f9nuri@gcp-sa-cloud-sql.iam.gserviceaccount.com:roles/storage.objectCreator gs://database_export
```

Grant object read permission for the storage bucket.

```
gsutil iam ch serviceAccount:p196247013763-f9nuri@gcp-sa-cloud-sql.iam.gserviceaccount.com:roles/storage.objectViewer gs://database_export
```

## 2. Export and import database

Run Google Cloud SDK as administrator. Ensure SDK is up-to-date:

```
gcloud components update
```

Create the SQL dump from the target_database using the following command:

```
gcloud sql export sql target-instance gs://database_export/sqldumpfile.gz --database=target_database
```

If the replica database already exists, remove it.

```
gcloud sql databases delete replica_database --instance=target-instance, -i target-instance
```

Create a new replica database

```
gcloud sql databases create replica_database --instance=target-instance
```

Import the SQL dump to a new database

```
gcloud sql import sql target-instance gs://database_export/sqldumpfile.gz --database=replica_database
```

The replica_database will now contain the data version from the SQL dump file.

The read access privileges will need to be reset by the administrative user. In the database query console (i.e. <u>not</u> in the Google Cloud Shell), the following command should be run:

```
GRANT USAGE ON SCHEMA public TO read_access;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO read_access;
```

