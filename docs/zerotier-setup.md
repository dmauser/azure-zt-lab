# ZeroTier setup

[ZeroTier](https://www.zerotier.com/) provides the encrypted overlay network that
connects the **hub-nva** (Azure) and **onprem-nva** (simulated on‑premises) in both
lab scenarios. This guide creates a network and explains the one manual step you
perform in the ZeroTier portal after each deployment.

## 1. Create a free account and a network

1. Sign up at [my.zerotier.com](https://my.zerotier.com/).
2. Go to **Networks → Create A Network**.
3. Open the network and note its **Network ID** (16 hex characters). You supply
   this to `deploy.sh` at deploy time.

## 2. Recommended network configuration

In the network's settings page:

| Setting | Value | Why |
| --- | --- | --- |
| Access Control | **Private** | Members must be authorized before they can join — safer for a lab. |
| IPv4 Auto‑Assign | Enable a range, e.g. `172.27.0.0/24` | Gives each NVA an overlay IP. Avoid overlap with the Azure/on‑prem ranges (`10.0.0.0/16`, `192.168.100.0/24`). |
| Managed Routes | *(optional)* | Not required — routing between sites is handled by the NVAs (static UDRs in Scenario 1, BGP in Scenario 2). |

![Network configuration – step 1](./images/step1-ztconfig.png)

![Network configuration – step 2](./images/step2-ztconfig.png)

## 3. Authorize the NVAs (post‑deploy)

`deploy.sh` installs ZeroTier on **hub-nva** and **onprem-nva** and joins them to
your network. Because the network is **Private**, they appear as *unauthorized*
members until you approve them:

1. Open your network at [my.zerotier.com](https://my.zerotier.com/).
2. Under **Members**, tick **Auth?** for the two new nodes.
3. Confirm each received an overlay IP from your auto‑assign range. You can pin a
   fixed IP per node here so the addresses stay stable across reboots.

![Authorized members with overlay IPs](./images/zerotier-network-members.png)

> Tip: identify which member is which by running `sudo zerotier-cli info` /
> `sudo zerotier-cli listnetworks` on each NVA (the node ID is shown in both).

## 4. Verify the overlay

SSH to each NVA (via its public IP) and confirm the tunnel is up:

```bash
sudo zerotier-cli listnetworks      # STATUS should be OK
ip addr show zt+                    # overlay interface + assigned IP
ping <other-nva-overlay-ip>         # end-to-end across the overlay
```

Once both NVAs can ping each other over the overlay, return to the scenario
README to finish routing configuration and run the connectivity tests.