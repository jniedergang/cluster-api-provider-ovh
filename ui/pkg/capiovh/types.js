export interface OVHClusterTopologyVariables {
  serviceName: string;
  region: string;
  identitySecretName: string;
  subnetCIDR: string;
  vlanID: number;
  lbFlavor: 'small' | 'medium' | 'large' | 'xl';
  floatingNetworkID: string;
  cpFlavor: string;
  workerFlavor: string;
  image: string;
  sshKeyName: string;
  rancherServerCA: string;
  disableCloudController: boolean;
  registryMirror: string;
  nodeDrainTimeout: string;
  etcdS3Endpoint: string;
  etcdS3Bucket: string;
  etcdS3CredentialsSecret: string;
}

export interface ClusterCreateRequest {
  name: string;
  namespace: string;
  clusterClass: 'ovhcloud-rke2' | 'ovhcloud-kubeadm';
  version: string;
  cpReplicas: number;
  workerReplicas: number;
  variables: Partial<OVHClusterTopologyVariables>;
  autoImport: boolean;
}

export const DEFAULTS: OVHClusterTopologyVariables = {
  serviceName:            '',
  region:                 'EU-WEST-PAR',
  identitySecretName:     'ovh-credentials',
  subnetCIDR:             '10.42.0.0/24',
  vlanID:                 0,
  lbFlavor:               'small',
  floatingNetworkID:      '',
  cpFlavor:               'b3-16',
  workerFlavor:           'b3-8',
  image:                  'Ubuntu 22.04',
  sshKeyName:             '',
  rancherServerCA:        '',
  disableCloudController: false,
  registryMirror:         '',
  nodeDrainTimeout:       '5m',
  etcdS3Endpoint:         '',
  etcdS3Bucket:           '',
  etcdS3CredentialsSecret: '',
};

export const OVH_REGIONS = [
  'EU-WEST-PAR',
  'GRA7', 'GRA9', 'GRA11',
  'SBG5',
  'BHS5',
  'WAW1',
  'DE1',
  'UK1',
  'SGP1',
  'SYD1',
  'US-EAST-VA-1', 'US-WEST-OR-1',
];

export const LB_FLAVORS = ['small', 'medium', 'large', 'xl'];

export const K8S_VERSIONS = [
  'v1.32.4+rke2r1',
  'v1.31.8+rke2r1',
  'v1.30.12+rke2r1',
];
