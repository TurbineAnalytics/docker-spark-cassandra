#!/bin/sh
crontab cassandra_backup_cronjob.txt
service cron start
