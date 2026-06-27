# Secure Azure Hub-and-Spoke Network Architecture

Enterprise-grade Azure infrastructure deployment featuring a secure Hub-Spoke topology, high availability, private data access, and real-time monitoring.

## Architecture Overview

![Network Topology](./screenshots/01-network-topology.png)

## What Was Built

- **Hub VNet** (`vnet-hub`): Central management network hosting Azure Bastion for secure VM access without public IPs
- **Spoke VNet** (`vnet-spoke`): Workload network divided into three isolated subnets
- **Load Balancer**: Distributes traffic across two Ubuntu VMs running Nginx
- **Private Endpoint**: Azure Blob Storage accessible only via private IP — zero public internet exposure
- **NSGs + ASGs**: Traffic restricted by VM identity, not just IP ranges
- **Azure Monitor**: Centralized logging, CPU alert rule, and operational dashboard

## Network Design

| Resource | Value |
|---|---|
| Hub VNet | 10.0.0.0/22 |
| AzureBastionSubnet | 10.0.0.0/26 |
| snet-hub-mgmt | 10.0.1.0/24 |
| Spoke VNet | 10.1.0.0/22 |
| snet-spoke-ingress | 10.1.0.0/24 |
| snet-spoke-web | 10.1.1.0/24 |
| snet-spoke-data | 10.1.2.0/24 |

## Screenshots

### Network Topology
![Topology](./screenshots/01-network-topology.png)

### Load Balancer Traffic Flow
![LB Topology](./screenshots/02-load-balancer-topology.png)

### Load Balancer Health
![LB Health](./screenshots/03-load-balancer-health.png)

### Storage Private Endpoint
![Storage](./screenshots/04-storage-private-endpoint.png)

### Azure Monitor Dashboard
![Dashboard](./screenshots/05-azure-monitor-dashboard.png)

### Live Website
![Website](./screenshots/06-live-website.png)

## Troubleshooting Scenarios

### Scenario A: VMs cannot reach Storage
- Check Private Endpoint DNS resolves to private IP
- Verify NSG on snet-spoke-data allows traffic from asg-web-servers
- Confirm VM NIC is attached to asg-web-servers ASG

### Scenario B: Load Balancer degraded availability
- Check health probe status in Azure Monitor
- Verify Nginx is running: `sudo systemctl status nginx`
- Check NSG allows port 80 inbound from internet

## Deploy This Infrastructure

```bash
az group create --name rg-hub-spoke-network --location uksouth
az deployment group create --resource-group rg-hub-spoke-network --template-file main.bicep
```

## Certifications
- Microsoft Azure Administrator (AZ-104)
- Microsoft Azure Fundamentals (AZ-900)