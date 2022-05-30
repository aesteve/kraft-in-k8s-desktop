resource "kubernetes_namespace" "kafka_ns" {
  metadata {
    name = "kafka"
  }
}

resource "kubernetes_service" "kafka_svc" {
  metadata {
    name = "kafka-headless"
    namespace = kubernetes_namespace.kafka_ns.id
    labels = {
      app = "broker"
    }
  }
  spec {
    cluster_ip = "None"
    selector = {
      app = "broker"
    }
    port {
      name = "external"
      protocol = "TCP"
      port = 9092
      target_port = 9092
    }
    port {
      name = "internal"
      protocol = "TCP"
      port = 9091
      target_port = 9091
    }
    port {
      name = "controller"
      protocol = "TCP"
      port = 29093
      target_port = 29093
    }
  }
}

resource "kubernetes_config_map" "scripts" {
  metadata {
    name = "scripts"
    namespace = kubernetes_namespace.kafka_ns.id
  }
  data = {
    "update_run.sh" = <<EOF
      #!/bin/sh
      # Docker workaround: Remove check for KAFKA_ZOOKEEPER_CONNECT parameter
      sed -i '/KAFKA_ZOOKEEPER_CONNECT/d' /etc/confluent/docker/configure
      # Docker workaround: Ignore cub zk-ready
      sed -i 's/cub zk-ready/echo ignore zk-ready/' /etc/confluent/docker/ensure
      # KRaft required step: Format the storage directory with a new cluster ID
      echo "kafka-storage format -t 3Db5QLSqSZieL3rJBUUegA -c /etc/kafka/kafka.properties" >> /etc/confluent/docker/ensure
    EOF
  }
}



resource "kubernetes_stateful_set" "kraft_in_k8s" {
  metadata {
    namespace = kubernetes_namespace.kafka_ns.id
    name = "broker"
    labels = {
      app = "broker"
    }
  }
  spec {
    service_name = "kafka-headless"
    replicas = 3

    selector {
      match_labels = {
        app = "broker"
      }
    }

    template {
      metadata {
        labels = {
          app = "broker"
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
          name  = "broker"
          volume_mount {
            name       = "update-run"
            mount_path = "/tmp/scripts"
          }
          command = ["/bin/bash", "-c", "--" ]
          args = [
            "if [ ! -f /tmp/scripts/update_run.sh ]; then echo \"ERROR: Did you forget the update_run.sh file that came with this docker-compose.yml file?\" && exit 1 ; else /tmp/scripts/update_run.sh && export KAFKA_ID=$$(($${POD_NAME##*-} + 1)) && export KAFKA_BROKER_ID=$$KAFKA_ID && export KAFKA_NODE_ID=$$KAFKA_ID && export KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://:29092,INTERNAL://$${POD_NAME}.kafka-headless.${kubernetes_namespace.kafka_ns.id}:9092,EXTERNAL://localhost:9092 && /etc/confluent/docker/run ; fi"
#            "if [ ! -f /tmp/scripts/update_run.sh ]; then echo \"ERROR: Did you forget the update_run.sh file that came with this docker-compose.yml file?\" && exit 1 ; else /tmp/scripts/update_run.sh && export KAFKA_ID=$$(($${POD_NAME##*-} + 1)) && export KAFKA_BROKER_ID=$$KAFKA_ID && export KAFKA_NODE_ID=$$KAFKA_ID && export KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://:29092,INTERNAL://$${POD_NAME}.kafka-headless.${kubernetes_namespace.kafka_ns.id}:9092,EXTERNAL://localhost:9092 && printf \"node_id=$$KAFKA_NODE_ID\n\" && printf \"broker_id=$$KAFKA_BROKER_ID\" && sleep 9999999 ; fi"

          ]
#          command = [ "/bin/bash", "-c", "--" ]
#          args = [ "while true; do sleep 30; done;" ]
          env {
            name = "KAFKA_CLUSTER_ID"
            value = "3Db5QLSqSZieL3rJBUUegA"
          }
          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
# Using env. variable POD_NAME instead
#          env {
#            name = "KAFKA_BROKER_ID"
#            value = "1"
#          }
#          env {
#            name = "KAFKA_NODE_ID"
#            value = "1"
#          }
          env {
            name = "KAFKA_PROCESS_ROLES"
            value = "broker,controller"
          }
          env {
            name = "KAFKA_CONTROLLER_QUORUM_VOTERS"
            value = "1@broker-0.kafka-headless.${kubernetes_namespace.kafka_ns.id}.svc.cluster.local:29093,2@broker-1.kafka-headless.${kubernetes_namespace.kafka_ns.id}.svc.cluster.local:29093,3@broker-2.kafka-headless.${kubernetes_namespace.kafka_ns.id}.svc.cluster.local:29093"
          }
          env {
            name = "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP"
            value = "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT"
          }
          env {
            name = "KAFKA_LISTENERS"
            value = "PLAINTEXT://:29092,CONTROLLER://:29093,INTERNAL://0.0.0.0:9091,EXTERNAL://0.0.0.0:9092"
          }
          env {
            name = "KAFKA_INTER_BROKER_LISTENER_NAME"
            value = "PLAINTEXT"
          }
          env {
            name = "KAFKA_CONTROLLER_LISTENER_NAMES"
            value = "CONTROLLER"
          }
#          env {
#            name = "KAFKA_ADVERTISED_LISTENERS"
#            value = "PLAINTEXT://:29092,EXTERNAL://localhost:9092"
#          }
          env {
            name = "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name = "KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS"
            value = "0"
          }
          env {
            name = "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR"
            value = "1"
          }
          env {
            name = "KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR"
            value = "1"
          }
          env {
            name = "KAFKA_LOG_DIRS"
            value = "/tmp/kraft-combined-logs"

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
            container_port  = 9092
            name            = "external-port"
          }
          port {
            container_port  = 9091
            name            = "internal-port"
          }
          port {
            container_port  = 29093
            name            = "controller-port"
          }
          # TODO: appropriate resources here
          # TODO: liveness_probe here
        }
      }
    }
  }
}