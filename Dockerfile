FROM cassandra:3.5

# add webupd8 repository
RUN \
    echo "===> add webupd8 repository..."  && \
    echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" | tee /etc/apt/sources.list.d/webupd8team-java.list  && \
    echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" | tee -a /etc/apt/sources.list.d/webupd8team-java.list  && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys EEA14886  && \
    apt-get update  && \
    \
    \
    echo "===> install Java"  && \
    echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections  && \
    echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections  && \
    DEBIAN_FRONTEND=noninteractive  apt-get install -y --force-yes oracle-java8-installer oracle-java8-set-default  && \
    \
    \
    echo "===> clean up..."  && \
    rm -rf /var/cache/oracle-jdk8-installer  && \
    apt-get clean  && \
    rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME /usr/lib/jvm/java-8-oracle

# install and configure supervisor + curl
RUN apt-get update && apt-get install -y supervisor curl && rm -rf /var/lib/apt/lists/* && mkdir -p /var/log/supervisor
#COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY supervisor.conf/ /supervisor.conf/
ENV SUPERVISOR_CONF_DEFAULT "/supervisor.conf/supervisord-cass.conf"
ENV SUPERVISOR_CONF_CASSANDRA "/supervisor.conf/supervisord-cass.conf"
ENV SUPERVISOR_CONF_MASTER "supervisor.conf/supervisord-master.conf"
ENV SUPERVISOR_CONF_WORKER "/supervisor.conf/supervisord-worker.conf"

# download and install spark
RUN curl -s http://www-eu.apache.org/dist/spark/spark-2.2.0/spark-2.2.0-bin-hadoop2.7.tgz | tar -xz -C /usr/local/
RUN cd /usr/local && ln -s spark-2.2.0-bin-hadoop2.7 spark

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
COPY scripts/start-master.sh /start-master.sh
COPY scripts/start-worker.sh /start-worker.sh
COPY scripts/spark-shell.sh /spark-shell.sh
COPY scripts/spark-cassandra-connector.jar /spark-cassandra-connector.jar
COPY scripts/spark-defaults.conf /spark-defaults.conf
COPY conf/log4j-server.properties /app/log4j-server.properties
COPY conf/spark-env.sh /usr/local/spark/conf/spark-env.sh

# configure spark
ENV SPARK_HOME /usr/local/spark
ENV SPARK_MASTER_OPTS="-Dspark.driver.port=7001 -Dspark.fileserver.port=7002 -Dspark.broadcast.port=7003 -Dspark.replClassServer.port=7004 -Dspark.blockManager.port=7005 -Dspark.executor.port=7006 -Dspark.ui.port=4040 -Dspark.broadcast.factory=org.apache.spark.broadcast.HttpBroadcastFactory"
ENV SPARK_WORKER_OPTS=$SPARK_MASTER_OPTS
ENV SPARK_MASTER_PORT 7077
ENV SPARK_MASTER_WEBUI_PORT 8080
ENV SPARK_WORKER_PORT 8888
ENV SPARK_WORKER_WEBUI_PORT 8081

# configure cassandra
ENV CASSANDRA_CONFIG /etc/cassandra

# listen to all rpc
RUN sed -ri 's/^(rpc_address:).*/\1 0.0.0.0/;' "$CASSANDRA_CONFIG/cassandra.yaml"
RUN sed -ri '/authenticator: AllowAllAuthenticator/c\authenticator: PasswordAuthenticator' "$CASSANDRA_CONFIG/cassandra.yaml"
RUN sed -ri '/authorizer: AllowAllAuthorizer/c\authorizer: CassandraAuthorizer' "$CASSANDRA_CONFIG/cassandra.yaml"
RUN sed -ri '/endpoint_snitch: SimpleSnitch/c\endpoint_snitch: GossipingPropertyFileSnitch' "$CASSANDRA_CONFIG/cassandra.yaml"
RUN sed -i -e '$a\JVM_OPTS="$JVM_OPTS -Dcassandra.metricsReporterConfigFile=metrics_reporter.yaml"' "$CASSANDRA_CONFIG/cassandra-env.sh"
RUN sed -i '/# set jvm HeapDumpPath with CASSANDRA_HEAPDUMP_DIR/a CASSANDRA_HEAPDUMP_DIR="/var/log/cassandra"' "$CASSANDRA_CONFIG/cassandra-env.sh"

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
