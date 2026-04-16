export function init(plugin, store) {
  const {
    product,
    basicType,
    virtualType,
  } = plugin.DSL(store, 'capiovh');

  product({
    inStore:             'management',
    icon:                'cluster',
    label:               'OVH Cloud',
    removable:           false,
    showClusterSwitcher: false,
    to:                  {
      name:   'c-cluster-capiovh',
      params: { product: 'capiovh' },
    },
  });

  virtualType({
    labelKey:  'capiovh.nav.clusters',
    name:      'capiovh-clusters',
    route:     {
      name:   'c-cluster-capiovh',
      params: { product: 'capiovh' },
    },
    icon:      'cluster',
    weight:    100,
  });

  virtualType({
    labelKey:  'capiovh.nav.create',
    name:      'capiovh-create',
    route:     {
      name:   'c-cluster-capiovh-create',
      params: { product: 'capiovh' },
    },
    icon:      'plus',
    weight:    90,
  });

  basicType([
    'capiovh-clusters',
    'capiovh-create',
  ]);
}
