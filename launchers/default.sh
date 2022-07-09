#!/bin/bash

source /environment.sh

# initialize launch file
dt-launchfile-init

# YOUR CODE BELOW THIS LINE
# ----------------------------------------------------------------------------

# default values
true ${INTERFACE:=wlan0}
true ${AP_ADDR:=192.168.254.1}

# check if we are running in client mode (jumper off)
if dt-wifi-jumper-missing; then
    echo "[INFO] Jumper NOT detected, wifi AP is disabled, using client mode instead."

    # enable client mode
    echo "[INFO] Anabling wifi client..."
    dt-set-trigger wifi-client on
    sleep 5
    echo "[INFO] Wifi client enabled."

    # remove fixed IP from device
    ip addr del ${AP_ADDR}/24 dev ${INTERFACE} | :

    exit 0
else
    echo "[INFO] Jumper detected, wifi AP is enabled."

    # disable client mode
    echo "[INFO] Disabling wifi client..."
    dt-set-trigger wifi-client off
    sleep 5
    echo "[INFO] Wifi client disabled."

    # check if running in privileged mode
    if [ ! -w "/sys" ] ; then
        echo "[Error] Not running in privileged mode."
        exit 1
    fi

    # default values
    set -e
    true ${GATEWAY:=eth0}
    true ${SUBNET:=192.168.254.0}
    true ${SSID:=$(INTERFACE=${INTERFACE} dt-wifi-ssid)}
    true ${CHANNEL:=11}
    true ${WPA_PASSPHRASE:=quackquack}
    true ${HW_MODE:=g}
    true ${DRIVER:=nl80211}
    true ${HT_CAPAB:=[HT40-][SHORT-GI-20]}

    # configure hostapd
    if [ ! -f "/etc/hostapd.conf" ] ; then
        cat > "/etc/hostapd.conf" <<EOF
interface=${INTERFACE}
driver=${DRIVER}
ssid=${SSID}
hw_mode=${HW_MODE}
channel=${CHANNEL}
wpa=2
wpa_passphrase=${WPA_PASSPHRASE}
wpa_key_mgmt=WPA-PSK
# TKIP is no secure anymore
#wpa_pairwise=TKIP CCMP
wpa_pairwise=CCMP
rsn_pairwise=CCMP
wpa_ptk_rekey=600
ieee80211n=1
ht_capab=${HT_CAPAB}
wmm_enabled=1
EOF
    fi

    # unblock wlan
    rfkill unblock wlan

    # setup interface and restart DHCP service
    echo "Setting interface ${INTERFACE}"
    ip link set ${INTERFACE} up
    ip addr flush dev ${INTERFACE}
    ip addr add ${AP_ADDR}/24 dev ${INTERFACE}

    # configure NAT: IP forwarding
    echo "Configuring NAT: ip_dynaddr / ip_forward"
    for i in ip_dynaddr ip_forward ; do
      if [ $(cat /proc/sys/net/ipv4/$i) ]; then
        echo "${i} already set to 1"
      else
        echo "1" > /proc/sys/net/ipv4/$i
      fi
    done

    # configure routes
    echo "Setting iptables for outgoing traffics on ${GATEWAY}..."
    iptables -t nat -D POSTROUTING -s ${SUBNET}/24 -o ${GATEWAY} -j MASQUERADE > /dev/null 2>&1 || true
    iptables -t nat -A POSTROUTING -s ${SUBNET}/24 -o ${GATEWAY} -j MASQUERADE

    iptables -D FORWARD -i ${GATEWAY} -o ${INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT > /dev/null 2>&1 || true
    iptables -A FORWARD -i ${GATEWAY} -o ${INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT

    iptables -D FORWARD -i ${INTERFACE} -o ${GATEWAY} -j ACCEPT > /dev/null 2>&1 || true
    iptables -A FORWARD -i ${INTERFACE} -o ${GATEWAY} -j ACCEPT

    # configure DHCP server
    echo "Configuring DHCP server..."
    cat > "/etc/dhcp/dhcpd.conf" <<EOF
option domain-name-servers 8.8.8.8, 8.8.4.4;
option subnet-mask 255.255.255.0;
subnet ${SUBNET} netmask 255.255.255.0 {
  range ${SUBNET::-1}100 ${SUBNET::-1}200;
}
EOF

    # run DHCP server
    echo "Starting DHCP server..."
    dt-exec dhcpd ${INTERFACE}

    # TODO: we have to catch the exit code of `hostapd` and return it to docker so that `restart: on-failure` can do its thing
    echo "Starting HostAP daemon..."
    dt-exec hostapd /etc/hostapd.conf

    set +e

    # ----------------------------------------------------------------------------
    # YOUR CODE ABOVE THIS LINE

    # wait for app to end
    dt-launchfile-join

    # clear previously added routes
    echo "Removing iptables for outgoing traffics on ${GATEWAY}..."
    iptables -t nat -D POSTROUTING -s ${SUBNET}/24 -o ${GATEWAY} -j MASQUERADE > /dev/null 2>&1 || true
    iptables -D FORWARD -i ${GATEWAY} -o ${INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT > /dev/null 2>&1 || true
    iptables -D FORWARD -i ${INTERFACE} -o ${GATEWAY} -j ACCEPT > /dev/null 2>&1 || true
fi
