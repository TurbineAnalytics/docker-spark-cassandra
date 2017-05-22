#!/bin/sh
crontab /backup/cassandra_backup_cronjob.txt
service cron start
