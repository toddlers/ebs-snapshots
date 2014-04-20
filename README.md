EBS-Snapshot and Rotation 
==============

## Tasks  
  1. Taking EBS timely snapshots
  2. Deleting them based on the age
  3. Tag them appropriately

## SYNOPSIS
ebs_snapshot.rb -c config.yaml


## Example config

```
# AWS credentials
provider: 'aws'
aws_access_key_id: '<AWS_ACCESS_KEY_ID>'
aws_secret_key: '<AWS_SECRET_KEY>'
aws_region: '<AWS_REGION>'

# specify the volumes
volumes:
  <volume_id>:
    :lifetime: "<retention_time>"
    :host: "<hostname>"
    :type: "<frequency for taking snapshots>"
# Example
  vol-ebb71aa7:
    :lifetime: 1
    :host: "blah.foo.com"
    :type: "hourly" # you can specify daily as well
```
- Two types of lifetime daily and hourly
  - if snapshot type is daily ,then lifetime is considered in days
  - if snapshot type is hourly ,then lifetime is considered in hours.

## Example Runs

```
λ: ruby ebs_snapshot.rb -c config.yaml

Creating snapshots 2014-04-20 23:27:10 +0530
Snapshot created Successfully
Checking snapshot es01p:hourly:2014-04-20:23:27
Checking snapshot es02p:daily:2014-04-20:23:27
Checking snapshot es02p:daily:2014-04-19:12:41
Checking snapshot es01p:hourly:2014-04-19:12:41
deleteing snapshot snap-1c4878c0
Deleted old snapshots

```

## Dependencies
  - ruby
  - fog
