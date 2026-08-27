# Scenario 1 — On‑premises to Azure over ZeroTier (static routing)

Connect a simulated **on‑premises** site to an Azure **hub‑and‑spoke** network
through an encrypted [ZeroTier](https://www.zerotier.com/) overlay, using two
Linux **network virtual appliances (NVAs)** and **static user‑defined routes
(UDRs)**.

This is the classic, dependency‑free pattern: routing is explicit and
deterministic. For the dynamic/BGP equivalent, see
[Scenario 2](../scenario2-dynamic-bgp/README.md).

## End‑to‑end walkthrough

1. **Deploy** the infrastructure — `./deploy.sh` (~5–8 min).
2. **Authorize** the two NVAs on the ZeroTier network — automatic when you supply
   an API token, otherwise manual in the portal.
3. **Apply routes** — automatic after API authorization, or run
   `./apply-routes.sh` after manual authorization.
4. **Verify** persistent NVA routes and bidirectional workload connectivity.
5. **Clean up** — `./cleanup.sh`.

Overlay IP plan (pinned automatically by `deploy.sh`):

| Node | Overlay IP |
| --- | --- |
| `hub-nva` | `172.27.0.10` |
| `onprem-nva` | `172.27.0.20` |

## Network diagram

![Scenario 1 network diagram](../docs/images/scenario1-diagram.png)

Editable source: [`scenario1-diagram.mmd`](../docs/images/scenario1-diagram.mmd)

| VNet | Address space | Subnets | Notes |
| --- | --- | --- | --- |
| hub‑vnet | `10.0.0.0/24` | `subnet1` `10.0.0.0/27`, `nvasubnet` `10.0.0.32/27` | hub‑nva at `10.0.0.36` |
| spoke1‑vnet | `10.0.1.0/24` | `subnet1` `10.0.1.0/27` | peered to hub |
| spoke2‑vnet | `10.0.2.0/24` | `subnet1` `10.0.2.0/27` | peered to hub |
| onprem‑vnet | `192.168.100.0/24` | `subnet1` `192.168.100.0/27`, `nvasubnet` `192.168.100.32/27` | onprem‑nva at `192.168.100.36` |

### How traffic flows

* **Spoke ↔ on‑prem:** `spoke1-vm1 → hub-nva` (spoke UDR) → **ZeroTier overlay** →
  `onprem-nva → onprem-vm1` (on‑prem UDR).
* **Hub ↔ on‑prem:** `hub-vm1 → hub-nva` → overlay → `onprem-nva → onprem-vm1`.
* **Intra‑Azure (hub ↔ spoke):** direct via **VNet peering** — the more‑specific
  system route wins over the `10.0.0.0/8` UDR, so hub/spoke traffic never
  needlessly hairpins through the NVA.
* NVAs use **static private IPs** so the UDR next‑hops are deterministic, and
  have **IP forwarding** enabled on the NIC.
* Each NVA has a persistent systemd route to the remote site through the
  opposite ZeroTier address. Azure UDRs alone do not configure the Linux RIB.
* Workload default routes use the local NVA for explicit, masqueraded Internet
  egress; no workload VM has a public IP.

## Prerequisites

* An Azure subscription and the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az login`).
* [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (bundled with recent `az`).
* A ZeroTier network and optional **Legacy Central API token** — see [../docs/zerotier-setup.md](../docs/zerotier-setup.md). Have your **Network ID** ready.
* `bash`, `curl`, `base64`, and `jq` (Cloud Shell has all four; `jq` is used by the authorization automation).
* An **OpenSSH client** and SSH public key (`ssh-keygen -t ed25519`).

## Deploy

```bash
cd scenario1-static-routing
export ZEROTIER_API_TOKEN="<your-token>"   # optional; enables auto-authorization
./deploy.sh
```

`deploy.sh` will:

1. Prompt for resource group, region, VM size, admin username, **SSH public
   key**, allowed SSH source, and your **ZeroTier Network ID**.
2. Lock SSH to your current public IP (auto‑detected, override‑able).
3. Build Bicep, validate the ARM deployment, display `what-if`, then deploy with
   an exact timestamped deployment name.
4. Wait for cloud-init, install ZeroTier on both NVAs, and join the network.
5. **Authorize both NVAs and pin their overlay IPs** (`172.27.0.10` / `172.27.0.20`)
   via the ZeroTier API when a token is available — otherwise it prints the manual
   portal steps (see [../docs/zerotier-setup.md](../docs/zerotier-setup.md)).
6. Install and verify persistent remote-site routes on both NVAs.

For repeatable runs, use `./deploy.sh --help`. Flags have matching environment
variables, and `LAB_SKIP_WHAT_IF=1` is available for an already-reviewed rerun.
If authorization is left manual, `deploy.sh` exits with status `2` to indicate
that routing is pending rather than complete.

## Verify

```bash
# Overlay and persistent guest route:
az vm run-command invoke -g <rg> -n hub-nva --command-id RunShellScript \
  --scripts "sudo zerotier-cli listnetworks; ip route show 192.168.100.0/24"
az vm run-command invoke -g <rg> -n onprem-nva --command-id RunShellScript \
  --scripts "ip route show 10.0.0.0/16; ping -c 4 172.27.0.10"

# End-to-end from the private on-prem workload:
az vm run-command invoke -g <rg> -n onprem-vm1 --command-id RunShellScript \
  --scripts "ping -c 4 10.0.1.4; curl --fail http://10.0.2.4"

# Reverse path from a private spoke workload:
az vm run-command invoke -g <rg> -n spoke1-vm1 --command-id RunShellScript \
  --scripts "ping -c 4 192.168.100.4; curl --fail http://192.168.100.4"

# Confirm the UDRs are programmed on a spoke NIC:
az network nic show-effective-route-table -g <rg> -n spoke1-vm1-nic \
  --query "value[?nextHopType=='VirtualAppliance'].[addressPrefix[0], nextHopIpAddress[0]]" -o tsv
# Expect: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16  all -> 10.0.0.36
```

## What gets deployed

| Type | Resources |
| --- | --- |
| VNets | hub, spoke1, spoke2, onprem (+ subnets) |
| NSGs | `default-nsg` for private workloads; `nva-nsg` for RFC1918 forwarding and source-restricted SSH |
| Route tables | hub‑udr, spoke1‑udr, spoke2‑udr, onprem‑udr, including explicit default egress |
| NVAs | `hub-nva`, `onprem-nva` (IP‑forwarding, static private IP, public administration/egress IP) |
| VMs | four private-only workload VMs |
| Peerings | spoke1 ↔ hub, spoke2 ↔ hub |

## Clean up

```bash
./cleanup.sh          # confirms resource-group deletion and optional member removal
./cleanup.sh --wait   # wait until Azure confirms deletion
```

> **Cost:** six small Ubuntu VMs, managed disks, and two NVA public IPs. Delete
> the resource group when you're done to avoid ongoing charges.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Deployment pauses at package installation | `az vm run-command invoke -g <rg> -n hub-nva --command-id RunShellScript --scripts "sudo cloud-init status --long"` |
| ZeroTier member is missing or unauthorized | Confirm the 16-character network ID, managed route, token scope, and `sudo zerotier-cli listnetworks` output. |
| Remote-site route is absent | Re-run `./apply-routes.sh`; inspect `systemctl status zt-lab-static-routes` on the affected NVA. |
| One-way workload connectivity | Check both NVA guest routes, NIC IP forwarding, effective UDRs, and `sysctl net.ipv4.ip_forward`. |
