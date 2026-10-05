# Rocky Linux 2-NIC Router / Internet Gateway

## 1. Purpose

This document describes how to configure a Rocky Linux server with two network interfaces as a router/NAT gateway for a laptop connected through a switch.

### Final topology

```
                         INTERNET
                            |
                        192.168.8.1
                            |
                         eno1 (WAN)
                       192.168.15.148/21
                            |
                    +------------------+
                    |  Rocky Linux     |
                    |   Router/NAT     |
                    +------------------+
                            |
                         eno2 (LAN)
                          10.10.10.1/24
                            |
                          Switch
                            |
                          Laptop
                       10.10.10.20/24
```

## 2. Network details

### Rocky Linux server

| Interface | Purpose | Address |
| --- | --- | --- |
| `eno1` | WAN / Internet | `192.168.15.148/21` |
| `eno2` | LAN / Switch | `10.10.10.1/24` |

WAN gateway:

```
192.168.8.1
```

LAN network:

```
10.10.10.0/24
```

### Laptop

Example static configuration:

```
IP address:       10.10.10.20
Subnet mask:      255.255.255.0
Default gateway:  10.10.10.1
DNS server:       8.8.8.8
```

## 3. Verify the server interfaces

On Rocky Linux:

```bash
ip -br addr
```

Expected result should be similar to:

```
eno1    UP    192.168.15.148/21
eno2    UP    10.10.10.1/24
```

Check routing:

```bash
ip route
```

Expected:

```
default via 192.168.8.1 dev eno1
10.10.10.0/24 dev eno2
192.168.8.0/21 dev eno1
```

## 4. Test Internet access from the Rocky server

Before configuring routing, verify that the Rocky server itself has Internet access:

```bash
ping -c 4 192.168.8.1
ping -c 4 8.8.8.8
ping -c 4 google.com
```

The server must be able to reach the Internet before it can provide Internet access to the LAN.

## 5. Enable IPv4 forwarding

Enable forwarding immediately:

```bash
sysctl -w net.ipv4.ip_forward=1
```

Verify:

```bash
sysctl net.ipv4.ip_forward
```

Expected:

```
net.ipv4.ip_forward = 1
```

Make it persistent:

```bash
cat > /etc/sysctl.d/99-router.conf <<'EOF'
net.ipv4.ip_forward = 1
EOF
```

Apply:

```bash
sysctl --system
```

## 6. Disable reverse-path filtering for this router

For this setup, disable `rp_filter` on the router interfaces:

```bash
cat >> /etc/sysctl.d/99-router.conf <<'EOF'
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.eno1.rp_filter = 0
net.ipv4.conf.eno2.rp_filter = 0
EOF
```

Apply:

```bash
sysctl --system
```

Verify:

```bash
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.eno1.rp_filter
sysctl net.ipv4.conf.eno2.rp_filter
```

## 7. Configure NAT with nftables

The LAN network is `10.10.10.0/24` and the Internet-facing interface is `eno1`.

Create the NAT table and chain:

```bash
nft add table ip nat
nft 'add chain ip nat postrouting { type nat hook postrouting priority 100; policy accept; }'
```

Add masquerading:

```bash
nft add rule ip nat postrouting oifname "eno1" ip saddr 10.10.10.0/24 masquerade
```

This changes traffic from the LAN so it can use the Rocky server's WAN address when going to the Internet.

## 8. Configure forwarding

Create the forwarding table and chain:

```bash
nft add table ip filter
nft 'add chain ip filter forward { type filter hook forward priority 0; policy drop; }'
```

Allow LAN traffic to go to the Internet:

```bash
nft add rule ip filter forward iifname "eno2" oifname "eno1" accept
```

Allow return traffic from the Internet back to the LAN:

```bash
nft add rule ip filter forward iifname "eno1" oifname "eno2" accept
```

The second rule is intentionally broad in this working lab configuration. It can be tightened later with connection tracking:

```
ct state established,related
```

## 9. Verify nftables

Run:

```bash
nft list ruleset
```

The important configuration should look approximately like:

```
table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "eno1" ip saddr 10.10.10.0/24 masquerade
    }
}

table ip filter {
    chain forward {
        type filter hook forward priority filter; policy drop;
        iifname "eno2" oifname "eno1" accept
        iifname "eno1" oifname "eno2" accept
    }
}
```

## 10. Configure the laptop

Connect the Rocky server's `eno2` to the switch.

Connect the laptop to the same switch.

The laptop should have:

```
IP:       10.10.10.20
Mask:     255.255.255.0
Gateway:  10.10.10.1
DNS:      8.8.8.8
```

## 11. Test from the laptop

### Test 1: LAN connectivity

```bash
ping -c 4 10.10.10.1
```

Expected: replies from `10.10.10.1`.

### Test 2: Internet by IP

```bash
ping -c 4 8.8.8.8
```

Expected: replies from `8.8.8.8`.

### Test 3: DNS

```bash
ping -c 4 google.com
```

If Test 2 works but Test 3 fails, the routing/NAT is working and the remaining problem is DNS.

## 12. Troubleshooting

### Check the laptop route

On Linux:

```bash
ip route
```

There should be a default route similar to:

```
default via 10.10.10.1
```

### Check packets entering the LAN interface

On Rocky:

```bash
tcpdump -ni eno2 icmp
```

Then from the laptop:

```bash
ping -c 4 8.8.8.8
```

You should see:

```
10.10.10.20 > 8.8.8.8: ICMP echo request
```

### Check packets leaving the WAN interface

On Rocky:

```bash
tcpdump -ni eno1 icmp
```

Then from the laptop:

```bash
ping -c 4 8.8.8.8
```

You should see traffic similar to:

```
192.168.15.148 > 8.8.8.8: ICMP echo request
8.8.8.8 > 192.168.15.148: ICMP echo reply
```

### Check packets returning to the LAN

```bash
tcpdump -ni eno2 icmp
```

You should eventually see the reply going back toward:

```
10.10.10.20
```

## 13. Make the nftables configuration persistent

The commands above create rules in the running kernel. They should be saved so they survive a reboot.

First make sure the nftables package is installed:

```bash
dnf install -y nftables
```

Create a clean permanent ruleset:

```bash
nft list ruleset >> /etc/sysconfig/nftables.conf
```

or if you added the previous rules into the current boot just write them declaratively 

```bash
cat >> /etc/sysconfig/nftables.conf <<'EOF'
#!/usr/sbin/nft -f

flush ruleset

table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "eno1" ip saddr 10.10.10.0/24 masquerade
    }
}

table ip filter {
    chain forward {
        type filter hook forward priority filter; policy drop;
        iifname "eno2" oifname "eno1" accept
        iifname "eno1" oifname "eno2" accept
    }
}
EOF
```

Test the file:

```bash
nft -c -f /etc/nftables.conf
```

If there are no errors, load it:

```bash
nft -f /etc/nftables.conf
```

Enable nftables at boot:

```bash
systemctl enable --now nftables
```

Verify:

```bash
systemctl status nftables
```

Then:

```bash
nft list ruleset
```

## 14. Make the LAN IP persistent

If `eno2` is not already permanently configured by NetworkManager, configure it with `nmcli`.

Find the connection name:

```bash
nmcli connection show
```

Then configure the connection associated with `eno2`. For example, if its connection name is `LAN`:

```bash
nmcli connection modify "LAN" \
  ipv4.method manual \
  ipv4.addresses 10.10.10.1/24 \
  ipv4.never-default yes \
  ipv6.method disabled
```

Bring it up:

```bash
nmcli connection up "LAN"
```

Verify:

```bash
ip -br addr
ip route
```

Important: do **not** configure a default gateway on `eno2`. The default gateway belongs on the WAN interface `eno1`.

## 15. Final verification after reboot

After all configuration is persistent, reboot the Rocky server:

```bash
reboot
```

After it comes back, verify:

```bash
ip -br addr
```

```bash
ip route
```

```bash
sysctl net.ipv4.ip_forward
```

```bash
nft list ruleset
```

Then from the laptop:

```bash
ping -c 4 10.10.10.1
ping -c 4 8.8.8.8
ping -c 4 google.com
```

## 16. Final configuration summary

```
SERVER
======

WAN:
  Interface: eno1
  IP:        192.168.15.148/21
  Gateway:   192.168.8.1

LAN:
  Interface: eno2
  IP:        10.10.10.1/24
  Gateway:   none

Routing:
  IPv4 forwarding: enabled

NAT:
  10.10.10.0/24 -> eno1
  masquerade enabled

SWITCH:
  eno2 -> switch
  laptop -> same switch

LAPTOP:
  IP:       10.10.10.20
  Mask:     255.255.255.0
  Gateway:  10.10.10.1
  DNS:      8.8.8.8
```

## 17. Traffic flow

```
Laptop
10.10.10.20
     |
     | 10.10.10.0/24
     v
Switch
     |
     v
Rocky eno2
10.10.10.1
     |
     | IP forwarding + NAT
     v
Rocky eno1
192.168.15.148
     |
     v
Gateway
192.168.8.1
     |
     v
Internet
```