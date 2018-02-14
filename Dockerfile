FROM cassandra:3.5

# auto validate license
RUN echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections

# update repos
RUN 	echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" | tee /etc/apt/sources.list.d/webupd8team-java.list && \
	echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" | tee -a /etc/apt/sources.list.d/webupd8team-java.list && \
	apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886 && \
	apt-get update && \
	apt-get install oracle-java8-installer -y --allow-unauthenticated || echo ''

# patch installer
RUN 	cd /var/lib/dpkg/info && \
	sed -i 's|JAVA_VERSION=8u151|JAVA_VERSION=8u161|' oracle-java8-installer.* && \
	sed -i 's|PARTNER_URL=http://download.oracle.com/otn-pub/java/jdk/8u151-b12/e758a0de34e24606bca991d704f6dcbf/|PARTNER_URL=http://download.oracle.com/otn-pub/java/jdk/8u161-b12/2f38c3b165be4555a1fa6e98c45e0808/|' oracle-java8-installer.* && \
	sed -i 's|SHA256SUM_TGZ="c78200ce409367b296ec39be4427f020e2c585470c4eed01021feada576f027f"|SHA256SUM_TGZ="6dbc56a0e3310b69e91bb64db63a485bd7b6a8083f08e48047276380a0e2021e"|' oracle-java8-installer.* && \
	sed -i 's|J_DIR=jdk1.8.0_151|J_DIR=jdk1.8.0_161|' oracle-java8-installer.* && \
	apt-get install oracle-java8-installer -y --allow-unauthenticated && \
	apt-get clean

ENV JAVA_HOME /usr/lib/jvm/java-8-oracle

# install and configure supervisor + curl
RUN apt-get update && apt-get install -y supervisor curl && rm -rf /var/lib/apt/lists/* && mkdir -p /var/log/supervisor

COPY supervisor.conf/ /supervisor.conf/
ENV SUPERVISOR_CONF_DEFAULT="/supervisor.conf/supervisord-cass.conf" SUPERVISOR_CONF_CASSANDRA="/supervisor.conf/supervisord-cass.conf" SUPERVISOR_CONF_MASTER="supervisor.conf/supervisord-master.conf" \
SUPERVISOR_CONF_WORKER="/supervisor.conf/supervisord-worker.conf"

# download and install spark
RUN 	curl -s http://www-eu.apache.org/dist/spark/spark-2.2.0/spark-2.2.0-bin-hadoop2.7.tgz | tar -xz -C /usr/local/ && \
	cd /usr/local && ln -s spark-2.2.0-bin-hadoop2.7 spark

RUN 	mkdir spark-libs && \
	wget http://central.maven.org/maven2/com/google/guava/guava/16.0.1/guava-16.0.1.jar -P spark-libs && \
	wget http://central.maven.org/maven2/net/finmath/finmath-lib/3.0.14/finmath-lib-3.0.14.jar -P spark-libs && \
	wget http://central.maven.org/maven2/org/scalaz/scalaz-core_2.11/7.2.3/scalaz-core_2.11-7.2.3.jar -P spark-libs && \
	wget http://central.maven.org/maven2/org/apache/commons/commons-math3/3.6.1/commons-math3-3.6.1.jar -P spark-libs && \
	wget http://central.maven.org/maven2/org/apache/commons/commons-lang3/3.4/commons-lang3-3.4.jar -P spark-libs && \
	wget http://central.maven.org/maven2/org/jblas/jblas/1.2.4/jblas-1.2.4.jar -P spark-libs && \
	wget http://central.maven.org/maven2/org/threeten/threetenbp/1.3.4/threetenbp-1.3.4.jar -P spark-libs && \
	wget http://central.maven.org/maven2/com/google/code/gson/gson/2.7/gson-2.7.jar -P spark-libs && \
	mv spark-libs/*.jar usr/local/spark/jars && \
	rm -rf spark-libs && \
  	cd usr/local/spark/jars && \
	rm guava-14.0.1.jar

RUN apt-get update \
    && apt-get install -y --no-install-recommends libjemalloc1 \
    && apt-get install net-tools \
    && apt-get install -y cron \
    && rm -rf /var/lib/apt/lists/*

# copy necessary files for backups to work
COPY backup/ /backup

# enable cron logging
RUN touch /var/log/cron.log

# copy some script to run spark
COPY ["scripts/start-master.sh", "scripts/start-worker.sh", "scripts/spark-shell.sh", "scripts/spark-cassandra-connector.jar", "scripts/spark-defaults.conf", "./"]
COPY conf/log4j-server.properties /app/log4j-server.properties
COPY conf/spark-env.sh /usr/local/spark/conf/spark-env.sh

# configure spark
ENV SPARK_HOME=/usr/local/spark SPARK_MASTER_OPTS="-Dspark.driver.port=7001 -Dspark.fileserver.port=7002 -Dspark.broadcast.port=7003 -Dspark.replClassServer.port=7004 -Dspark.blockManager.port=7005 -Dspark.executor.port=7006 -Dspark.ui.port=4040 -Dspark.broadcast.factory=org.apache.spark.broadcast.HttpBroadcastFactory" SPARK_WORKER_OPTS=$SPARK_MASTER_OPTS \
SPARK_MASTER_PORT=7077 SPARK_MASTER_WEBUI_PORT=8080 SPARK_WORKER_PORT=8888 SPARK_WORKER_WEBUI_PORT=8081 CASSANDRA_CONFIG=/etc/cassandra

# listen to all rpc
RUN 	sed -ri 's/^(rpc_address:).*/\1 0.0.0.0/;' "$CASSANDRA_CONFIG/cassandra.yaml" && \  
	sed -ri '/authenticator: AllowAllAuthenticator/c\authenticator: PasswordAuthenticator' "$CASSANDRA_CONFIG/cassandra.yaml" && \
	sed -ri '/authorizer: AllowAllAuthorizer/c\authorizer: CassandraAuthorizer' "$CASSANDRA_CONFIG/cassandra.yaml" && \
	sed -ri '/endpoint_snitch: SimpleSnitch/c\endpoint_snitch: GossipingPropertyFileSnitch' "$CASSANDRA_CONFIG/cassandra.yaml" && \
	sed -i -e '$a\JVM_OPTS="$JVM_OPTS -Dcassandra.metricsReporterConfigFile=metrics_reporter.yaml"' "$CASSANDRA_CONFIG/cassandra-env.sh" && \
	sed -i '/# set jvm HeapDumpPath with CASSANDRA_HEAPDUMP_DIR/a CASSANDRA_HEAPDUMP_DIR="/var/log/cassandra"' "$CASSANDRA_CONFIG/cassandra-env.sh"

COPY cassandra-configurator.sh /cassandra-configurator.sh
COPY update_users.sh /update_users.sh
COPY conf/metrics_reporter.yaml $CASSANDRA_CONFIG/metrics_reporter.yaml

ENTRYPOINT ["/cassandra-configurator.sh"]

### Spark
# 4040: spark ui
# 7001: spark driver
# 7002: spark fileserver
# 7003: spark broadcast
# 7004: spark replClassServer
# 7005: spark blockManager
# 7006: spark executor
# 7077: spark master
# 8080: spark master ui
# 8081: spark worker ui
# 8888: spark worker
### Cassandra
# 7000: C* intra-node communication
# 7199: C* JMX
# 9042: C* CQL
# 9160: C* thrift service
EXPOSE 4040 7000 7001 7002 7003 7004 7005 7006 7077 7199 8080 8081 8888 9042 9160

CMD ["cassandra"]

