# Architecture & Design Decisions

## 🏗️ Infrastructure Choices & Rationale

### Cloud Provider: AWS
**Rationale:**
- **EKS**: Managed Kubernetes reduces operational overhead while maintaining flexibility
- **Global presence**: Multi-region capability for future expansion
- **Integrated services**: Native load balancers, storage, IAM, and monitoring
- **Cost optimization**: Spot instances, auto-scaling, and granular billing
- **Enterprise-ready**: SOC2, ISO compliance for production workloads

### Instance Types Selection

#### Rollup Nodes (m6i.xlarge)
- **vCPUs**: 4 cores for parallel transaction processing
- **Memory**: 16 GB for in-memory state caching
- **Network**: Up to 12.5 Gbps for high-throughput RPC
- **Storage**: EBS-optimized for consistent IOPS
- **Rationale**: Balanced compute/memory for blockchain workloads

#### Ethereum Nodes (m6i.2xlarge)
- **vCPUs**: 8 cores for proof generation and validation
- **Memory**: 32 GB for state trie and mempool
- **Network**: Up to 12.5 Gbps for peer connectivity
- **Storage**: EBS-optimized with dedicated bandwidth
- **Rationale**: Higher specs for L1 consensus participation

### Storage & I/O Profile

#### Storage Configuration
```yaml
GP3 Volumes:
- Base IOPS: 3000
- Throughput: 125 MB/s
- Encryption: AES-256
- Snapshots: Daily incremental
```

**I/O Optimization:**
- **Separate volumes** for chaindata, logs, and snapshots
- **Read-ahead tuning** for sequential blockchain reads
- **Write caching** disabled for data integrity
- **RAID-0** consideration for multi-volume throughput

### Network Architecture

#### Security Layers
```
Internet → ALB/NLB → Public Subnet → NAT Gateway → Private Subnet → Pods
                          ↓                              ↓
                    (LoadBalancer)                  (Blockchain Nodes)
```

**Security Controls:**
- **Network isolation**: Private subnets for compute
- **Security groups**: Port-specific ingress rules
- **NACLs**: Subnet-level defense-in-depth
- **JWT auth**: Secure inter-component communication

#### Performance Optimization
- **Placement groups**: Co-locate related pods
- **Enhanced networking**: SR-IOV for low latency
- **Cross-AZ traffic**: Minimized via topology-aware routing
- **DNS caching**: CoreDNS optimization for service discovery

### Performance Isolation Strategy

#### Resource Segregation
```yaml
Node Groups:
  rollup-nodes:
    - Dedicated to L2 components
    - Spot instances for cost optimization
    - Horizontal scaling based on RPC load
  
  ethereum-nodes:
    - Dedicated to L1 components
    - On-demand for stability
    - Tainted to prevent other workloads
```

#### Quality of Service (QoS)
- **Guaranteed QoS**: Fixed resource allocation for critical pods
- **CPU Manager**: Static policy for consistent performance
- **Memory limits**: Prevent OOM killer interference
- **Pod anti-affinity**: Distribute replicas across nodes

### Scaling to Three Nodes

#### Horizontal Scaling Strategy
```bash
# StatefulSet configuration enables ordered scaling
kubectl scale statefulset op-geth -n rollup --replicas=3
```

**Benefits:**
- **Load distribution**: Round-robin RPC requests
- **Fault tolerance**: Survive single node failure
- **Read scaling**: Parallel query processing
- **State sync**: Automated via P2P network

#### Considerations
- **Storage**: 3x volume costs
- **Network**: Inter-pod sync traffic
- **Consistency**: Eventually consistent reads
- **Leader election**: For write operations

## 📊 Monitoring Strategy

### Infrastructure Layer Metrics

#### Cluster Health
```promql
# Node availability
up{job="kubernetes-nodes"} == 1

# CPU pressure
rate(node_cpu_seconds_total{mode="idle"}[5m]) < 0.1

# Memory pressure
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.1

# Disk pressure
node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes < 0.1
```

#### Network Performance
- **Latency**: P50, P95, P99 percentiles
- **Throughput**: Bytes/sec in/out
- **Errors**: Dropped packets, retransmissions
- **Connections**: Active/established counts

### Application Layer Metrics

#### Blockchain Health
```promql
# Block height lag
ethereum_block_height - op_geth_block_height > 10

# Peer connectivity
p2p_peer_count < 5

# Transaction pool
txpool_pending_transactions > 1000

# State sync progress
sync_percentage < 100
```

#### RPC Performance
- **Request rate**: Queries per second
- **Response time**: Method-specific latency
- **Error rate**: 4xx/5xx responses
- **Queue depth**: Pending requests

### Business Layer Metrics

#### Synthetic KPIs
```promql
# Transaction throughput (TPS)
rate(eth_rpc_transactions_total[1m])

# Cost per transaction
sum(node_cost_per_hour) / rate(transactions_processed[1h])

# Availability SLI
(1 - rate(http_requests_total{status=~"5.."}[5m])) * 100

# Sync efficiency
rate(blocks_processed[5m]) / rate(blocks_produced[5m])
```

#### Custom Dashboards
- **Executive**: Cost, TPS, availability
- **Operations**: Health, performance, alerts
- **Development**: Detailed metrics, traces

## 🚀 Performance Optimization

### System-Level Tuning

#### Kernel Parameters
```bash
# Network optimization
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728

# File system
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
```

#### Container Runtime
- **CPU pinning**: Dedicate cores to critical pods
- **NUMA awareness**: Memory locality optimization
- **Huge pages**: Reduce TLB misses
- **I/O scheduler**: `deadline` for predictable latency

### Application-Level Optimization

#### Blockchain Client Tuning
```yaml
op-geth:
  cache: 4096          # Increase state cache
  txpool.pricebump: 5  # Reduce reorg overhead
  maxpeers: 100        # Balance connectivity/overhead
  
op-node:
  l1.cache-size: 1000  # L1 block cache
  l2.batch-size: 100   # Batch transaction processing
```

#### Database Optimization
- **LevelDB tuning**: Bloom filters, compression
- **Write amplification**: Minimize via batching
- **Compaction**: Schedule during low-load periods
- **Cache warming**: Pre-load hot data

### Infrastructure Optimization

#### Cost-Performance Balance
```yaml
Spot Strategy:
  - Dev/Test: 100% spot instances
  - Production: 70% spot, 30% on-demand
  - Critical: 100% on-demand with reserved

Right-Sizing:
  - Monitor actual usage vs allocation
  - Implement vertical pod autoscaling
  - Use burstable instances where appropriate
```

#### Network Optimization
- **Service mesh**: Consider for advanced routing
- **CDN**: Cache static RPC responses
- **Connection pooling**: Reuse persistent connections
- **gRPC**: Binary protocol for internal APIs

## 🎯 Architecture Benefits

1. **High Availability**: Multi-AZ, auto-healing, redundant components
2. **Scalability**: Horizontal and vertical scaling paths
3. **Performance**: Optimized for blockchain workloads
4. **Security**: Defense-in-depth, zero-trust networking
5. **Observability**: Comprehensive monitoring stack
6. **Cost Efficiency**: Right-sized, spot instances, auto-scaling

## 🔄 Future Considerations

1. **Multi-Region**: Active-active deployment
2. **Caching Layer**: Redis for RPC response cache
3. **API Gateway**: Rate limiting, authentication
4. **Service Mesh**: Istio for advanced traffic management
5. **GitOps**: ArgoCD for declarative deployments 