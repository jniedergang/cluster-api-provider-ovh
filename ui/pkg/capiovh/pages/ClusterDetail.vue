<script>
import { mapGetters } from 'vuex';
import Banner from '@components/Banner/Banner';

const CAPI_CLUSTER = 'cluster.x-k8s.io.cluster';
const OVH_CLUSTER = 'infrastructure.cluster.x-k8s.io.ovhcluster';
const CAPI_MACHINE = 'cluster.x-k8s.io.machine';

export default {
  name:       'ClusterDetail',
  components: { Banner },

  async fetch() {
    const name = this.$route.params.id;
    const ns = this.$route.query.namespace || 'fleet-default';

    try {
      this.cluster = await this.$store.dispatch('management/find', {
        type: CAPI_CLUSTER,
        id:   `${ ns }/${ name }`,
      });

      const ovhClusters = await this.$store.dispatch('management/findAll', { type: OVH_CLUSTER });
      this.ovhCluster = ovhClusters.find(
        (o) => o.metadata?.ownerReferences?.some((r) => r.name === name)
      ) || ovhClusters.find((o) => o.metadata?.name?.startsWith(name));

      const allMachines = await this.$store.dispatch('management/findAll', { type: CAPI_MACHINE });
      this.machines = allMachines.filter(
        (m) => m.spec?.clusterName === name || m.metadata?.labels?.['cluster.x-k8s.io/cluster-name'] === name
      );
    } catch (e) {
      this.error = e?.message || 'Cluster introuvable';
    }
  },

  data() {
    return {
      cluster:    null,
      ovhCluster: null,
      machines:   [],
      error:      null,
      tab:        'overview',
      scaleDialog: false,
      newCPReplicas: 0,
      newWorkerReplicas: 0,
    };
  },

  computed: {
    ...mapGetters({ t: 'i18n/t' }),

    phase() { return this.cluster?.status?.phase || 'Unknown'; },
    version() { return this.cluster?.spec?.topology?.version || '-'; },
    endpoint() {
      const ep = this.cluster?.spec?.controlPlaneEndpoint || this.ovhCluster?.spec?.controlPlaneEndpoint;
      return ep ? `${ ep.host }:${ ep.port }` : '-';
    },
    cpReplicas() { return this.cluster?.spec?.topology?.controlPlane?.replicas || 0; },
    workerReplicas() {
      const mds = this.cluster?.spec?.topology?.workers?.machineDeployments;
      return mds?.[0]?.replicas || 0;
    },
    region() { return this.ovhCluster?.spec?.region || '-'; },
    ready() { return this.ovhCluster?.status?.ready || false; },
    conditions() { return this.ovhCluster?.status?.conditions || []; },
    failureDomains() { return this.ovhCluster?.status?.failureDomains || {}; },

    cpMachines() { return this.machines.filter((m) => !m.metadata?.labels?.['cluster.x-k8s.io/deployment-name']); },
    workerMachines() { return this.machines.filter((m) => m.metadata?.labels?.['cluster.x-k8s.io/deployment-name']); },

    phaseColor() {
      const p = this.phase;
      if (p === 'Provisioned') return 'success';
      if (p === 'Provisioning') return 'warning';
      if (p === 'Deleting') return 'error';
      return 'info';
    },
  },

  methods: {
    openScale() {
      this.newCPReplicas = this.cpReplicas;
      this.newWorkerReplicas = this.workerReplicas;
      this.scaleDialog = true;
    },

    async applyScale() {
      try {
        this.cluster.spec.topology.controlPlane.replicas = this.newCPReplicas;
        this.cluster.spec.topology.workers.machineDeployments[0].replicas = this.newWorkerReplicas;
        await this.cluster.save();
        this.scaleDialog = false;
      } catch (e) {
        this.error = e?.message;
      }
    },

    async downloadKubeconfig() {
      const name = this.cluster.metadata.name;
      const ns = this.cluster.metadata.namespace;

      try {
        const secret = await this.$store.dispatch('management/find', {
          type: 'secret',
          id:   `${ ns }/${ name }-kubeconfig`,
        });

        const content = atob(secret.data?.value || '');
        const blob = new Blob([content], { type: 'application/yaml' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${ name }.kubeconfig`;
        a.click();
        URL.revokeObjectURL(url);
      } catch (e) {
        this.error = 'Kubeconfig non disponible';
      }
    },

    async deleteCluster() {
      if (!confirm(`Supprimer le cluster "${ this.cluster.metadata.name }" ? Cette action est irreversible.`)) {
        return;
      }

      try {
        await this.cluster.remove();
        this.$router.push({
          name:   'c-cluster-capiovh',
          params: { product: 'capiovh' },
        });
      } catch (e) {
        this.error = e?.message;
      }
    },
  },
};
</script>

<template>
  <div v-if="cluster" class="cluster-detail">
    <!-- Header -->
    <header class="row mb-20">
      <div>
        <h1>{{ cluster.metadata.name }}</h1>
        <span :class="['badge', `bg-${phaseColor}`]">{{ phase }}</span>
        <span class="ml-10">{{ version }}</span>
        <span class="ml-10 text-muted">{{ region }}</span>
      </div>
      <div class="actions">
        <button class="btn role-secondary" @click="downloadKubeconfig">Kubeconfig</button>
        <button class="btn role-secondary" @click="openScale">Scale</button>
        <button class="btn role-danger" @click="deleteCluster">Supprimer</button>
      </div>
    </header>

    <Banner v-if="error" color="error" :label="error" />

    <!-- Tabs -->
    <div class="tabs mb-20">
      <button :class="['tab', { active: tab === 'overview' }]" @click="tab = 'overview'">Vue d'ensemble</button>
      <button :class="['tab', { active: tab === 'machines' }]" @click="tab = 'machines'">Machines ({{ machines.length }})</button>
      <button :class="['tab', { active: tab === 'conditions' }]" @click="tab = 'conditions'">Conditions</button>
    </div>

    <!-- Overview -->
    <div v-if="tab === 'overview'" class="tab-content">
      <table class="info-table">
        <tr><td>Endpoint</td><td>{{ endpoint }}</td></tr>
        <tr><td>CP Replicas</td><td>{{ cpReplicas }}</td></tr>
        <tr><td>Worker Replicas</td><td>{{ workerReplicas }}</td></tr>
        <tr><td>OVH Ready</td><td>{{ ready ? 'Oui' : 'Non' }}</td></tr>
        <tr><td>Network ID</td><td>{{ ovhCluster?.status?.networkID || '-' }}</td></tr>
        <tr><td>LB ID</td><td>{{ ovhCluster?.status?.loadBalancerID || '-' }}</td></tr>
        <tr><td>FIP ID</td><td>{{ ovhCluster?.status?.floatingIPID || '-' }}</td></tr>
        <tr><td>Failure Domains</td><td>{{ Object.keys(failureDomains).join(', ') || '-' }}</td></tr>
      </table>
    </div>

    <!-- Machines -->
    <div v-if="tab === 'machines'" class="tab-content">
      <h3>Control Plane ({{ cpMachines.length }})</h3>
      <table class="sortable-table">
        <thead><tr><th>Nom</th><th>Phase</th><th>Provider ID</th><th>Node</th><th>Age</th></tr></thead>
        <tbody>
          <tr v-for="m in cpMachines" :key="m.id">
            <td>{{ m.metadata.name }}</td>
            <td>{{ m.status?.phase }}</td>
            <td>{{ m.spec?.providerID || '-' }}</td>
            <td>{{ m.status?.nodeRef?.name || '-' }}</td>
            <td>{{ m.metadata.creationTimestamp }}</td>
          </tr>
        </tbody>
      </table>

      <h3 class="mt-20">Workers ({{ workerMachines.length }})</h3>
      <table class="sortable-table">
        <thead><tr><th>Nom</th><th>Phase</th><th>Provider ID</th><th>Node</th><th>Age</th></tr></thead>
        <tbody>
          <tr v-for="m in workerMachines" :key="m.id">
            <td>{{ m.metadata.name }}</td>
            <td>{{ m.status?.phase }}</td>
            <td>{{ m.spec?.providerID || '-' }}</td>
            <td>{{ m.status?.nodeRef?.name || '-' }}</td>
            <td>{{ m.metadata.creationTimestamp }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Conditions -->
    <div v-if="tab === 'conditions'" class="tab-content">
      <table class="sortable-table">
        <thead><tr><th>Type</th><th>Status</th><th>Message</th><th>Last Transition</th></tr></thead>
        <tbody>
          <tr v-for="c in conditions" :key="c.type">
            <td>{{ c.type }}</td>
            <td :class="c.status === 'True' ? 'text-success' : 'text-warning'">{{ c.status }}</td>
            <td>{{ c.message || '-' }}</td>
            <td>{{ c.lastTransitionTime }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Scale Dialog -->
    <div v-if="scaleDialog" class="modal-overlay" @click.self="scaleDialog = false">
      <div class="modal-content">
        <h3>Scaler le cluster</h3>
        <label>CP Replicas: <input v-model.number="newCPReplicas" type="number" min="1" max="5" /></label>
        <label>Worker Replicas: <input v-model.number="newWorkerReplicas" type="number" min="0" max="20" /></label>
        <div class="mt-10">
          <button class="btn role-primary" @click="applyScale">Appliquer</button>
          <button class="btn role-secondary ml-10" @click="scaleDialog = false">Annuler</button>
        </div>
      </div>
    </div>
  </div>

  <div v-else>
    <Banner v-if="error" color="error" :label="error" />
    <p v-else>Chargement...</p>
  </div>
</template>

<style scoped>
.badge { padding: 4px 8px; border-radius: 4px; color: white; font-size: 0.85em; }
.bg-success { background: var(--success); }
.bg-warning { background: var(--warning); }
.bg-error { background: var(--error); }
.bg-info { background: var(--info); }
.tabs { display: flex; gap: 10px; }
.tab { padding: 8px 16px; border: 1px solid var(--border); border-radius: 4px; cursor: pointer; background: var(--body-bg); }
.tab.active { border-color: var(--primary); background: var(--primary); color: white; }
.info-table td { padding: 6px 12px; }
.info-table td:first-child { font-weight: bold; width: 200px; }
.modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 1000; }
.modal-content { background: var(--body-bg); padding: 20px; border-radius: 8px; min-width: 400px; }
.modal-content label { display: block; margin: 10px 0; }
</style>
