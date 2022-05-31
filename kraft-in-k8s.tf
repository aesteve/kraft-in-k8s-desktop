resource "kubernetes_namespace" "kafka_ns" {
  metadata {
    name = "kafka"
  }
}

locals {
  cluster_id = "3Db5QLSqSZieL3rJBUUegA"
  ports = {
    "internal"    : {
      protocol  = "TCP"
      container = 9091,
      host      = 9091,
    },
    "external"    : {
      protocol  = "TCP"
      container = 9092,
      host      = 9092,
    },
    "controller"  : {
      protocol  = "TCP"
      container = 29093,
      host      = 29093
    }
  }
  controller_addresses =  [
    for i in range(var.nb_brokers) :
      # eg: 0@broker-0.kafka-svc.kafka.svc.cluster.local:9091
      "${i}@${var.broker_app_name}-${i}.${var.service_name}.${kubernetes_namespace.kafka_ns.id}.svc.cluster.local:${local.ports.controller.host}"
  ]
  start_exports      = [
    "export KAFKA_BROKER_ID=$${POD_NAME##*-}",
    "export KAFKA_NODE_ID=$${POD_NAME##*-}",
    "export KAFKA_ADVERTISED_LISTENERS=INTERNAL://$${POD_NAME}.${var.service_name}.${kubernetes_namespace.kafka_ns.id}:${local.ports.internal.host},EXTERNAL://${var.advertised_hostname}:${local.ports.external.host}",
  ]
  start_scripts       = [
    "/tmp/scripts/update_run.sh",
    "/etc/confluent/docker/run",
  ]
  broker_start_cmd     = join(" && ", concat(local.start_exports, local.start_scripts))
  broker_kafka_envs    = {
    "CLUSTER_ID": local.cluster_id,
    "PROCESS_ROLES": "broker,controller",
    "CONTROLLER_QUORUM_VOTERS": join(",", local.controller_addresses),
    "LISTENER_SECURITY_PROTOCOL_MAP": "CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT",
    "LISTENERS": "CONTROLLER://:${local.ports.controller.host},INTERNAL://:${local.ports.internal.host},EXTERNAL://:${local.ports.external.host}",
    # ADVERTISED_LISTENERS ==> at runtime (because depends on $POD_NAME)
    "INTER_BROKER_LISTENER_NAME": "INTERNAL",
    "CONTROLLER_LISTENER_NAMES": "CONTROLLER",
    "DEFAULT_REPLICATION_FACTOR": var.nb_brokers,
    "OFFSETS_TOPIC_REPLICATION_FACTOR": var.nb_brokers,
    "GROUP_INITIAL_REBALANCE_DELAY_MS": "0",
    "TRANSACTION_STATE_LOG_MIN_ISR": "1",
    "TRANSACTION_STATE_LOG_REPLICATION_FACTOR": "1",
    "KAFKA_LOG_DIRS": "/tmp/kraft-combined-logs"
  }
}

resource "kubernetes_service" "kafka_svc" {
  metadata {
    namespace = kubernetes_namespace.kafka_ns.id
    name = var.service_name
    labels = {
      app = var.broker_app_name
    }
  }
  spec {
    cluster_ip = "None"
    selector = {
      app = var.broker_app_name
    }
    dynamic "port" {
      for_each = local.ports
      content {
        name = port.key
        protocol = port.value.protocol
        port = port.value.host
        target_port = port.value.container
      }
    }
  }
}

resource "kubernetes_config_map" "scripts" {
  metadata {
    namespace = kubernetes_namespace.kafka_ns.id
    name = "scripts"
  }
  data = {
    "update_run.sh" = <<EOF
      #!/bin/sh
      # Docker workaround: Remove check for KAFKA_ZOOKEEPER_CONNECT parameter
      sed -i '/KAFKA_ZOOKEEPER_CONNECT/d' /etc/confluent/docker/configure
      # Docker workaround: Ignore cub zk-ready
      sed -i 's/cub zk-ready/echo ignore zk-ready/' /etc/confluent/docker/ensure
      # KRaft required step: Format the storage directory with a new cluster ID
      echo "kafka-storage format -t ${local.cluster_id} -c /etc/kafka/kafka.properties" >> /etc/confluent/docker/ensure
    EOF
  }
}

resource "kubernetes_stateful_set" "kraft_in_k8s" {
  metadata {
    namespace = kubernetes_namespace.kafka_ns.id
    name = var.broker_app_name
    labels = {
      app = var.broker_app_name
    }
  }
  spec {
    service_name = var.service_name
    replicas = var.nb_brokers
    selector {
      match_labels = {
        app = var.broker_app_name
      }
    }
    template {
      metadata {
        labels = {
          app = var.broker_app_name
        }
      }
      spec {
        volume {
          name = "update-run"
          config_map {
            name = "scripts"
            default_mode = "0777"
          }
        }
        container {
          image = "confluentinc/cp-kafka"
          name  = var.broker_app_name
          volume_mount {
            name       = "update-run"
            mount_path = "/tmp/scripts"
          }
          command = ["/bin/bash", "-c", "--" ]
          args = [ local.broker_start_cmd ]
          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          dynamic "env" {
            for_each = local.broker_kafka_envs
            content {
              name = "KAFKA_${env.key}"
              value = env.value
            }
          }
#          env {
#            name = "KAFKA_JMX_PORT"
#            value = "9101"
#          }
#          env {
#            name = "KAFKA_JMX_HOSTNAME"
#            value = "localhost"
#          }
          dynamic "port" {
            for_each = local.ports
            content {
              container_port = port.value.container
              name = port.key
            }
          }
          resources {
            requests = {
              cpu = 1
              memory = "256Mi"
            }
            limits = {
              cpu = 1
              memory = "1024Mi"
            }
          }
#          liveness_probe {
#            exec {
#              command = ["/usr/bin/jps | grep -q Kafka"]
#            }
#          }
#          readiness_probe {
#            tcp_socket {
#              port = "internal-port"
#            }
#            initial_delay_seconds = 1
#            period_seconds = 1
#            timeout_seconds = 1
#            success_threshold = 1
#            failure_threshold = 3
#          }
        }
      }
    }
  }
}
