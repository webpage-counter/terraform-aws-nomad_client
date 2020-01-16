#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive
set -x

mkdir -p /tmp/logs
mkdir -p /etc/consul.d


# Function used for initialize Consul. Requires 2 arguments: Log level and the hostname assigned by the respective variables.
# If no log level is specified in the main.tf, then default "info" is used.
init_consul () {
    killall consul

    LOG_LEVEL=$1
    if [ -z "$1" ]; then
        LOG_LEVEL="info"
    fi

    if [ -d /tmp/logs ]; then
    mkdir /tmp/logs
    LOG="/tmp/logs/$2.log"
    else
    LOG="consul.log"
    fi

    sudo useradd --system --home /etc/consul.d --shell /bin/false consul
    sudo chown --recursive consul:consul /etc/consul.d
    sudo chmod -R 755 /etc/consul.d/
    sudo mkdir --parents /tmp/consul
    sudo chown --recursive consul:consul /tmp/consul
    mkdir -p /tmp/consul_logs/
    sudo chown --recursive consul:consul /tmp/consul_logs/

    cat << EOF > /etc/systemd/system/consul.service
    [Unit]
    Description="HashiCorp Consul - A service mesh solution"
    Documentation=https://www.consul.io/
    Requires=network-online.target
    After=network-online.target

    [Service]
    User=consul
    Group=consul
    ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
    ExecReload=/usr/local/bin/consul reload
    KillMode=process
    Restart=on-failure
    LimitNOFILE=65536


    [Install]
    WantedBy=multi-user.target

EOF
}

# Function that creates the conf file for the Consul servers. 

create_server_conf () {
    cat << EOF > /etc/consul.d/config_${DCNAME}.json
    
    {
        
        "server": true,
        "node_name": "${var2}",
        "bind_addr": "${IP}",
        "client_addr": "0.0.0.0",
        "bootstrap_expect": ${SERVER_COUNT},
        "retry_join_wan": ["provider=aws tag_key=join_wan tag_value=${JOIN_WAN}"],
        "retry_join": ["provider=aws tag_key=consul tag_value=${DCNAME}"],
        "log_level": "${LOG_LEVEL}",
        "data_dir": "/tmp/consul",
        "enable_script_checks": true,
        "domain": "${DOMAIN}",
        "datacenter": "${DCNAME}",
        "ui": true,
        "disable_remote_exec": true,
        "connect": {
          "enabled": true
        },
        "ports": {
            "grpc": 8502
        }

    }
EOF
}

# Function that creates the conf file for Consul clients. 
create_client_conf() {
    cat << EOF > /etc/consul.d/consul_client.json

        {
            "node_name": "${var2}",
            "bind_addr": "${IP}",
            "client_addr": "0.0.0.0",
            "retry_join": ["provider=aws tag_key=consul tag_value=${DCNAME}"],
            "log_level": "${LOG_LEVEL}",
            "data_dir": "/tmp/consul",
            "enable_script_checks": true,
            "domain": "${DOMAIN}",
            "datacenter": "${DCNAME}",
            "ui": true,
            "disable_remote_exec": true,
            "leave_on_terminate": false,
            "ports": {
                "grpc": 8502
            },
            "connect": {
                "enabled": true
            }
        }

EOF
}

# Starting consul
init_consul ${LOG_LEVEL} ${var2} 
case "${DCNAME}" in
    "${DCNAME}")
    if [[ "${var2}" =~ "ip-10-123-1" || "${var2}" =~ "ip-10-124-1" ]]; then
        killall consul

        create_server_conf

        sudo systemctl enable consul >/dev/null
    
        sudo systemctl start consul >/dev/null
        sleep 5
    else
        if [[ "${var2}" =~ "ip-10-123-2" || "${var2}" =~ "ip-10-123-3" ]]; then
            killall consul
            create_client_conf
            sudo systemctl enable consul >/dev/null
            sudo systemctl start consul >/dev/null
        fi
    fi
    ;;
esac

sleep 5
consul members
consul members -wan






################### Nomad part of script #####################


# Function used for initialize Nomad. Requires 2 arguments: Log level and the hostname assigned by the respective variables.
# If no log level is specified in the Vagrantfile, then default "info" is used.
init_nomad () {
    killall nomad

    LOG_LEVEL=$1
    if [ -z "$1" ]; then
        LOG_LEVEL="info"
    fi

    if [ -d /tmp/logs ]; then
    mkdir -p /tmp/logs
    LOG="/tmp/logs/$2-nomad.log"
    else
    LOG="nomad.log"
    fi


    sudo sudo useradd -m -d /etc/nomad.d -s /bin/false nomad
    sudo chown --recursive nomad:nomad /etc/nomad.d
    sudo chmod -R 755 /etc/nomad.d/
    sudo mkdir --parents /tmp/nomad
    sudo chown --recursive nomad:nomad /tmp/nomad
    mkdir -p /tmp/nomad_logs/
    sudo chown --recursive nomad:nomad /tmp/nomad_logs/

    cat << EOF > /etc/systemd/system/nomad.service
[Unit]
Description=Nomad
Documentation=https://nomadproject.io/docs/
Wants=network-online.target
After=network-online.target

# If you are running Consul, please uncomment following Wants/After configs.
# Assuming your Consul service unit name is "consul"
Wants=consul.service
After=consul.service

[Service]
User=root
KillMode=process
KillSignal=SIGINT
ExecStart=/usr/local/bin/nomad agent -config /etc/nomad.d/
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=2
StartLimitBurst=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target

EOF
}

# Function that creates the conf file for the nomad servers. It requires 8 arguments. All of them are defined in the beginning of the script.
# Arguments 5 and 6 are the SOFIA_SERVERS and BTG_SERVERS and they are twisted depending in which DC you are creating the conf file.
create_server_conf () {
    cat << EOF > /etc/nomad.d/config_nomad_${DCNAME}.hcl
    
    data_dir  = "/tmp/nomad"

    log_level = "${LOG_LEVEL}"

    name    = "${var2}"

    datacenter = "${DCNAME}"

    bind_addr = "0.0.0.0" # the default

    advertise {
        # Defaults to the first private IP address.
        http = "{{ GetInterfaceIP \"enp0s8\" }}"
        rpc  = "{{ GetInterfaceIP \"enp0s8\" }}"
        serf = "{{ GetInterfaceIP \"enp0s8\" }}"
    }

    server {
        enabled          = true
        bootstrap_expect = ${SERVER_COUNT}
        server_join {
            retry_join = ["provider=aws tag_key=nomad tag_value=${DCNAME}"]
            retry_max = 3
            retry_interval = "15s"
        }
    }

    consul {
        address             = "127.0.0.1:8500"
        server_service_name = "nomad"
        client_service_name = "nomad-client"
        auto_advertise      = true
        
    }


    ports {
        http = 4646
        rpc  = 4647
        serf = 4648
    }

EOF
}

# Function that creates the conf file for nomad clients. It requires 6 arguments and they are defined in the beginning of the script.
# 3rd argument shall be the JOIN_SERVER as it points the client to which server contact for cluster join.
create_client_conf () {
    cat << EOF > /etc/nomad.d/nomad_client.hcl

        data_dir  = "/tmp/nomad"

        log_level = "${LOG_LEVEL}"

        name    = "${var2}"

        datacenter = "${DCNAME}"

        bind_addr = "0.0.0.0" # the default

        advertise {
            # Defaults to the first private IP address.
            http = "{{ GetInterfaceIP \"enp0s8\" }}"
            rpc  = "{{ GetInterfaceIP \"enp0s8\" }}"
            serf = "{{ GetInterfaceIP \"enp0s8\" }}"
        }

        client {
            enabled = true
            network_interface = "enp0s8"
            server_join {
                retry_join = ["provider=aws tag_key=nomad tag_value=${DCNAME}"]
                retry_max = 3
                retry_interval = "15s"
            }
            options = {
                "driver.raw_exec" = "1"
                "driver.raw_exec.enable" = "1"
                "driver.raw_exec.no_cgroups" = "1"
            }
        }

        consul {
            address             = "127.0.0.1:8500"
            server_service_name = "nomad"
            client_service_name = "nomad-client"
            auto_advertise      = true
        
        }

        ports {
            http = 4646
            rpc  = 4647
            serf = 4648
        }

EOF
}

# Starting Nomad

init_nomad ${LOG_LEVEL} ${var2} 

case "${DCNAME}" in
    "${DCNAME}")
    if [[ "${var2}" =~ "ip-10-123-2" || "${var2}" =~ "ip-10-124-2" ]]; then
        killall nomad

        create_server_conf

        sudo systemctl enable nomad >/dev/null
    
        sudo systemctl start nomad >/dev/null
        sleep 5
    else
        if [[ "${var2}" =~ "ip-10-123-3" || "${var2}" =~ "ip-10-123-3" ]]; then
            killall nomad
            create_client_conf
            sudo systemctl enable nomad >/dev/null
            sudo systemctl start nomad >/dev/null
        fi
    fi
    ;;
esac

sleep 5
nomad server members
nomad server members -wan
sudo usermod -aG docker nomad
set +x