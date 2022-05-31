resource "kubernetes_namespace" "kafka_ns" {
  metadata {
    name = "kafka"
  }
}

locals {
  controller_port      = 29093
  external_port        = 9092
  internal_port        = 9091
  cluster_id           = "3Db5QLSqSZieL3rJBUUegA"
  controller_addresses =  [
    for i in range(var.nb_brokers) :
      "${i}@${var.broker_app_name}-${i}.${var.service_name}.${kubernetes_namespace.kafka_ns.id}.svc.cluster.local:${local.controller_port}"
  ]
  export_commands      = [
    "export KAFKA_BROKER_ID=$${POD_NAME##*-}",
    "export KAFKA_NODE_ID=$${POD_NAME##*-}",
    "export KAFKA_ADVERTISED_LISTENERS=INTERNAL://$${POD_NAME}.${var.service_name}.${kubernetes_namespace.kafka_ns.id}:${local.internal_port},EXTERNAL://${var.advertised_hostname}:${local.external_port}",
  ]
  start_commands       = [
    "/tmp/scripts/update_run.sh",
    "/etc/confluent/docker/run",
  ]
  broker_start_cmd     = join(" && ", concat(local.export_commands, local.start_commands))
  broker_kafka_envs    = {
    "CLUSTER_ID": local.cluster_id,
    "PROCESS_ROLES": "broker,controller",
    "CONTROLLER_QUORUM_VOTERS": join(",", local.controller_addresses),
    "LISTENER_SECURITY_PROTOCOL_MAP": "CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT",
    "LISTENERS": "CONTROLLER://:${local.controller_port},INTERNAL://0.0.0.0:${local.internal_port},EXTERNAL://0.0.0.0:${local.external_port}",
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
    port {
      name = "external"
      protocol = "TCP"
      port = local.external_port
      target_port = local.external_port
    }
    port {
      name = "internal"
      protocol = "TCP"
      port = local.internal_port
      target_port = local.internal_port
    }
    port {
      name = "controller"
      protocol = "TCP"
      port = local.controller_port
      target_port = local.controller_port
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

          port {
            container_port  = local.external_port
            name            = "external-port"
          }
          port {
            container_port  = local.internal_port
            name            = "internal-port"
          }
          port {
            container_port  = local.controller_port
            name            = "controller-port"
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
