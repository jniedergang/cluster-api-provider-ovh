<script>
import { CAPI as RANCHER_CAPI } from '@shell/config/types';
import { CAPIOVH } from '../types/capiovh';
import Banner from '@components/Banner/Banner.vue';
import ovhLogo from '../assets/ovhcloud-logo.png';

export default {
  name: 'CAPIOVHDashboard',

  components: { Banner },

  async fetch() {
    try {
      const capiClusters = await this.$store.dispatch('management/findAll', { type: RANCHER_CAPI.CAPI_CLUSTER });

      this.clusters = (capiClusters || []).filter((c) => {
        const cc = c.spec?.topology?.class || '';
        return cc.includes('ovhcloud');
      });

      try {
        this.ovhClusters = await this.$store.dispatch('management/findAll', { type: CAPIOVH.OVH_CLUSTER });
      } catch (e) {
        // OVH CRD may not be available
      }
    } catch (e) {
      this.error = e?.message || 'Failed to load clusters';
    }
  },

  data() {
    return {
      clusters:    [],
      ovhClusters: [],
      error:       null,
      ovhLogo,
    };
  },

  computed: {
    clusterRows() {
      return this.clusters.map((c) => {
        const ovh = (this.ovhClusters || []).find(
          (o) => c.metadata?.name && o.metadata?.name?.startsWith(c.metadata.name)
        );

        return {
          name:      c.metadata?.name,
          namespace: c.metadata?.namespace,
          phase:     c.status?.phase || 'Unknown',
          version:   c.spec?.topology?.version || '-',
          cpReplicas: c.spec?.topology?.controlPlane?.replicas || 0,
          workerReplicas: c.spec?.topology?.workers?.machineDeployments?.[0]?.replicas || 0,
          region:    ovh?.spec?.region || '-',
          ready:     ovh?.status?.ready || false,
          age:       c.metadata?.creationTimestamp,
        };
      });
    },
  },

  methods: {
    phaseColor(phase) {
      if (phase === 'Provisioned') return 'bg-success';
      if (phase === 'Provisioning') return 'bg-warning';
      if (phase === 'Deleting') return 'bg-error';
      return 'bg-info';
    },
  },
};
</script>

<template>
  <div>
    <div class="header-row mb-20">
      <h1>
        <img
          :src="ovhLogo"
          style="height: 32px; vertical-align: middle; margin-right: 10px;"
        />
        OVH Cloud Kubernetes
      </h1>
      <button
        class="btn role-primary"
        @click="$router.push({ name: 'c-cluster-product-resource-create', params: { cluster: '_', product: 'manager', resource: 'cluster.x-k8s.io.cluster' } })"
      >
        Create Cluster
      </button>
    </div>

    <Banner
      v-if="error"
      color="error"
      :label="error"
    />

    <div
      v-if="!$fetchState.pending && clusters.length === 0 && !error"
      class="empty-state"
    >
      <h2>No OVH Cloud clusters yet</h2>
      <p>
        Create your first Kubernetes cluster on OVH Public Cloud using the
        <code>ovhcloud-rke2</code> ClusterClass. The cluster will be fully
        managed by Cluster API and integrated with Rancher.
      </p>
      <p class="text-muted mt-10">
        Migrating from OVHcloud Managed Kubernetes? CAPIOVH provides the
        same experience with full CAPI lifecycle management, MachineHealthCheck
        auto-remediation, and topology-based upgrades.
      </p>
    </div>

    <table
      v-if="clusterRows.length > 0"
      class="sortable-table"
    >
      <thead>
        <tr>
          <th>Name</th>
          <th>Namespace</th>
          <th>Phase</th>
          <th>Version</th>
          <th>Region</th>
          <th>CP</th>
          <th>Workers</th>
          <th>Ready</th>
          <th>Age</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="row in clusterRows"
          :key="row.name"
        >
          <td>{{ row.name }}</td>
          <td>{{ row.namespace }}</td>
          <td>
            <span :class="['badge', phaseColor(row.phase)]">{{ row.phase }}</span>
          </td>
          <td>{{ row.version }}</td>
          <td>{{ row.region }}</td>
          <td>{{ row.cpReplicas }}</td>
          <td>{{ row.workerReplicas }}</td>
          <td>
            <span :class="row.ready ? 'text-success' : 'text-warning'">
              {{ row.ready ? '✓' : '...' }}
            </span>
          </td>
          <td>{{ row.age }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.header-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.empty-state {
  text-align: center;
  padding: 60px 20px;
  max-width: 600px;
  margin: 0 auto;
}
.empty-state h2 { margin-bottom: 10px; }
.badge {
  padding: 3px 8px;
  border-radius: 3px;
  color: white;
  font-size: 0.85em;
}
.bg-success { background: #4CAF50; }
.bg-warning { background: #FF9800; }
.bg-error { background: #F44336; }
.bg-info { background: #2196F3; }
.text-success { color: #4CAF50; font-weight: bold; }
.text-warning { color: #FF9800; }
</style>
