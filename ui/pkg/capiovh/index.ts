import { importTypes } from '@rancher/auto-import';
import { IPlugin } from '@shell/core/types';

const CAPI_GROUP = 'cluster.x-k8s.io';
const INFRA_GROUP = 'infrastructure.cluster.x-k8s.io';
const PRODUCT_NAME = 'capiovh';

export default function(plugin: IPlugin) {
  importTypes(plugin);

  plugin.addProduct(require('./product'));

  plugin.metadata = {
    product:     [PRODUCT_NAME],
    category:    'cluster-management',
    description: 'Manage OVH Cloud Kubernetes clusters via CAPI',
    icon:        'cluster',
  };

  // Register CRD types so they appear in the Rancher resource explorer
  plugin.addSchemaType(`${INFRA_GROUP}.ovhcluster`, {
    product: PRODUCT_NAME,
    label:   'OVH Clusters',
    icon:    'cluster',
  });

  plugin.addSchemaType(`${INFRA_GROUP}.ovhmachine`, {
    product: PRODUCT_NAME,
    label:   'OVH Machines',
    icon:    'node',
  });

  plugin.addSchemaType(`${CAPI_GROUP}.cluster`, {
    product: PRODUCT_NAME,
    label:   'CAPI Clusters',
    icon:    'cluster',
  });
}
