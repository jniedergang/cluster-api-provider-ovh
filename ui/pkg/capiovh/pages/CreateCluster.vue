<script>
import { mapGetters } from 'vuex';
import Banner from '@components/Banner/Banner';
import LabeledInput from '@components/Form/LabeledInput/LabeledInput';
import LabeledSelect from '@shell/components/form/LabeledSelect';
import Checkbox from '@components/Form/Checkbox/Checkbox';
import {
  DEFAULTS, OVH_REGIONS, LB_FLAVORS, K8S_VERSIONS,
} from '../types';

const CAPI_CLUSTER = 'cluster.x-k8s.io.cluster';

export default {
  name:       'CreateCluster',
  components: { Banner, LabeledInput, LabeledSelect, Checkbox },

  data() {
    return {
      step:      1,
      creating:  false,
      error:     null,
      name:      '',
      namespace: 'fleet-default',

      // Credentials
      credentialSecretName: 'ovh-credentials',
      newCredentials:       false,
      endpoint:             'ovh-ca',
      applicationKey:       '',
      applicationSecret:    '',
      consumerKey:          '',

      // Infrastructure
      ...DEFAULTS,

      // Topology
      clusterClass:  'ovhcloud-rke2',
      version:       K8S_VERSIONS[0],
      cpReplicas:    1,
      workerReplicas: 1,

      // Options
      autoImport: true,

      // Constants
      OVH_REGIONS,
      LB_FLAVORS,
      K8S_VERSIONS,
      steps: [
        { num: 1, label: 'Credentials' },
        { num: 2, label: 'Infrastructure' },
        { num: 3, label: 'Machines' },
        { num: 4, label: 'Options' },
      ],
    };
  },

  computed: {
    ...mapGetters({ t: 'i18n/t' }),

    canCreate() {
      return this.name && this.serviceName && this.sshKeyName;
    },
  },

  methods: {
    next() { if (this.step < 4) this.step++; },
    prev() { if (this.step > 1) this.step--; },

    buildVariables() {
      const vars = [];
      const add = (name, value) => {
        if (value !== '' && value !== null && value !== undefined) {
          vars.push({ name, value });
        }
      };

      add('serviceName', this.serviceName);
      add('region', this.region);
      add('identitySecretName', this.credentialSecretName);
      add('subnetCIDR', this.subnetCIDR);
      add('vlanID', this.vlanID);
      add('lbFlavor', this.lbFlavor);
      add('floatingNetworkID', this.floatingNetworkID);
      add('cpFlavor', this.cpFlavor);
      add('workerFlavor', this.workerFlavor);
      add('image', this.image);
      add('sshKeyName', this.sshKeyName);

      if (this.rancherServerCA) add('rancherServerCA', this.rancherServerCA);
      if (this.disableCloudController) add('disableCloudController', true);
      if (this.registryMirror) add('registryMirror', this.registryMirror);
      if (this.nodeDrainTimeout !== '5m') add('nodeDrainTimeout', this.nodeDrainTimeout);
      if (this.etcdS3Endpoint) {
        add('etcdS3Endpoint', this.etcdS3Endpoint);
        add('etcdS3Bucket', this.etcdS3Bucket);
        add('etcdS3CredentialsSecret', this.etcdS3CredentialsSecret);
      }

      return vars;
    },

    async create() {
      this.creating = true;
      this.error = null;

      try {
        if (this.newCredentials) {
          await this.$store.dispatch('management/create', {
            type:     'secret',
            metadata: {
              name:      this.credentialSecretName,
              namespace: this.namespace,
            },
            stringData: {
              endpoint:          this.endpoint,
              applicationKey:    this.applicationKey,
              applicationSecret: this.applicationSecret,
              consumerKey:       this.consumerKey,
            },
          });
        }

        const labels = {};
        if (this.autoImport) {
          labels['cluster-api.cattle.io/rancher-auto-import'] = 'true';
        }

        const cluster = {
          type:     CAPI_CLUSTER,
          metadata: {
            name:      this.name,
            namespace: this.namespace,
            labels,
          },
          spec: {
            clusterNetwork: {
              pods:     { cidrBlocks: ['10.244.0.0/16'] },
              services: { cidrBlocks: ['10.96.0.0/16'] },
            },
            topology: {
              class:          this.clusterClass,
              classNamespace: this.namespace,
              version:        this.version,
              controlPlane:   { replicas: this.cpReplicas },
              workers:        {
                machineDeployments: [{
                  class:    'default-worker',
                  name:     'worker',
                  replicas: this.workerReplicas,
                }],
              },
              variables: this.buildVariables(),
            },
          },
        };

        await this.$store.dispatch('management/create', cluster);

        this.$router.push({
          name:   'c-cluster-capiovh',
          params: { product: 'capiovh' },
        });
      } catch (e) {
        this.error = e?.message || 'Erreur de creation';
      } finally {
        this.creating = false;
      }
    },
  },
};
</script>

<template>
  <div class="create-cluster">
    <h1>{{ t('capiovh.create.title') }}</h1>

    <Banner v-if="error" color="error" :label="error" />

    <!-- Step indicators -->
    <div class="steps mb-20">
      <span
        v-for="s in steps"
        :key="s.num"
        :class="['step', { active: step === s.num, done: step > s.num }]"
        @click="step = s.num"
      >
        {{ s.num }}. {{ s.label }}
      </span>
    </div>

    <!-- Step 1: Credentials -->
    <div v-if="step === 1" class="step-content">
      <h3>OVH API Credentials</h3>
      <LabeledInput v-model="credentialSecretName" label="Secret name" />
      <Checkbox v-model="newCredentials" label="Creer un nouveau Secret" />
      <div v-if="newCredentials">
        <LabeledSelect v-model="endpoint" label="Endpoint" :options="['ovh-eu','ovh-ca','ovh-us']" />
        <LabeledInput v-model="applicationKey" label="Application Key" type="password" />
        <LabeledInput v-model="applicationSecret" label="Application Secret" type="password" />
        <LabeledInput v-model="consumerKey" label="Consumer Key" type="password" />
      </div>
    </div>

    <!-- Step 2: Infrastructure -->
    <div v-if="step === 2" class="step-content">
      <h3>Infrastructure OVH</h3>
      <LabeledInput v-model="serviceName" label="Service Name (Project ID)" required />
      <LabeledSelect v-model="region" label="Region" :options="OVH_REGIONS" />
      <LabeledInput v-model="subnetCIDR" label="Subnet CIDR" />
      <LabeledInput v-model.number="vlanID" label="VLAN ID" type="number" min="0" max="4094" />
      <LabeledInput v-model="floatingNetworkID" label="Floating Network ID" />
      <LabeledInput v-model="sshKeyName" label="SSH Key Name" required />
      <LabeledSelect v-model="lbFlavor" label="Load Balancer Flavor" :options="LB_FLAVORS" />
    </div>

    <!-- Step 3: Machines -->
    <div v-if="step === 3" class="step-content">
      <h3>Machines</h3>
      <LabeledInput v-model="name" label="Cluster Name" required />
      <LabeledSelect v-model="clusterClass" label="ClusterClass" :options="['ovhcloud-rke2','ovhcloud-kubeadm']" />
      <LabeledSelect v-model="version" label="Kubernetes Version" :options="K8S_VERSIONS" />
      <LabeledInput v-model.number="cpReplicas" label="Control Plane Replicas" type="number" min="1" max="5" />
      <LabeledInput v-model="cpFlavor" label="CP Flavor" />
      <LabeledInput v-model.number="workerReplicas" label="Worker Replicas" type="number" min="0" max="20" />
      <LabeledInput v-model="workerFlavor" label="Worker Flavor" />
      <LabeledInput v-model="image" label="OS Image" />
    </div>

    <!-- Step 4: Options -->
    <div v-if="step === 4" class="step-content">
      <h3>Options avancees</h3>
      <Checkbox v-model="autoImport" label="Importer automatiquement dans Rancher" />
      <Checkbox v-model="disableCloudController" label="Desactiver le cloud-controller RKE2" />
      <LabeledInput v-model="registryMirror" label="Registry Mirror" placeholder="https://mirror.internal:5000" />
      <LabeledInput v-model="nodeDrainTimeout" label="Node Drain Timeout" />
      <h4 class="mt-20">Etcd S3 Backup</h4>
      <LabeledInput v-model="etcdS3Endpoint" label="S3 Endpoint" />
      <LabeledInput v-model="etcdS3Bucket" label="S3 Bucket" />
      <LabeledInput v-model="etcdS3CredentialsSecret" label="S3 Credentials Secret" />
      <h4 class="mt-20">Rancher</h4>
      <LabeledInput v-model="rancherServerCA" label="Rancher Server CA" type="multiline" />
    </div>

    <!-- Navigation -->
    <div class="actions mt-20">
      <button v-if="step > 1" class="btn role-secondary" @click="prev">Precedent</button>
      <button v-if="step < 4" class="btn role-primary" @click="next">Suivant</button>
      <button
        v-if="step === 4"
        class="btn role-primary"
        :disabled="!canCreate || creating"
        @click="create"
      >
        {{ creating ? 'Creation en cours...' : 'Creer le cluster' }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.steps {
  display: flex;
  gap: 20px;
}
.step {
  padding: 8px 16px;
  border-radius: 4px;
  cursor: pointer;
  background: var(--body-bg);
  border: 1px solid var(--border);
}
.step.active {
  background: var(--primary);
  color: white;
  border-color: var(--primary);
}
.step.done {
  background: var(--success);
  color: white;
  border-color: var(--success);
}
.step-content {
  max-width: 600px;
}
.actions {
  display: flex;
  gap: 10px;
}
</style>
