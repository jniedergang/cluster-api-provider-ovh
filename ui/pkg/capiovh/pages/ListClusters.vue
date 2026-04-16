<script>
import { mapGetters } from 'vuex';
import ResourceTable from '@shell/components/ResourceTable';
import Banner from '@components/Banner/Banner';

const CAPI_CLUSTER = 'cluster.x-k8s.io.cluster';
const OVH_CLUSTER = 'infrastructure.cluster.x-k8s.io.ovhcluster';

export default {
  name:       'ListClusters',
  components: { ResourceTable, Banner },

  async fetch() {
    const store = this.$store;

    try {
      this.clusters = await store.dispatch('management/findAll', { type: CAPI_CLUSTER });
      this.ovhClusters = await store.dispatch('management/findAll', { type: OVH_CLUSTER });
    } catch (e) {
      this.error = e?.message || 'Erreur de chargement';
    }
  },

  data() {
    return {
      clusters:    [],
      ovhClusters: [],
      error:       null,
    };
  },

  computed: {
    ...mapGetters({ t: 'i18n/t' }),

    filteredClusters() {
      return (this.clusters || []).filter((c) => {
        const cc = c.spec?.topology?.class || '';
        return cc.includes('ovhcloud');
      });
    },

    headers() {
      return [
        { name: 'name', labelKey: 'capiovh.list.name', value: 'metadata.name', sort: ['metadata.name'] },
        { name: 'namespace', labelKey: 'capiovh.list.namespace', value: 'metadata.namespace' },
        { name: 'phase', labelKey: 'capiovh.list.phase', value: 'status.phase' },
        { name: 'version', labelKey: 'capiovh.list.version', value: 'spec.topology.version' },
        { name: 'cp', labelKey: 'capiovh.list.cp', value: 'spec.topology.controlPlane.replicas' },
        { name: 'workers', labelKey: 'capiovh.list.workers', value: 'spec.topology.workers.machineDeployments.0.replicas' },
        { name: 'age', labelKey: 'capiovh.list.age', value: 'metadata.creationTimestamp', sort: ['metadata.creationTimestamp'] },
      ];
    },
  },

  methods: {
    goCreate() {
      this.$router.push({
        name:   'c-cluster-capiovh-create',
        params: { product: 'capiovh' },
      });
    },
  },
};
</script>

<template>
  <div>
    <header class="row mb-20">
      <h1>{{ t('capiovh.list.title') }}</h1>
      <button class="btn role-primary" @click="goCreate">
        {{ t('capiovh.list.create') }}
      </button>
    </header>

    <Banner v-if="error" color="error" :label="error" />

    <ResourceTable
      :rows="filteredClusters"
      :headers="headers"
      :loading="$fetchState.pending"
      key-field="id"
      default-sort-by="name"
    />
  </div>
</template>
