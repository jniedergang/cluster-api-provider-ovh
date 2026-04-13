# BYOI (Bring Your Own Image) sur OVH Public Cloud

OVH Public Cloud ne fournit pas d'images SUSE/SLES/openSUSE en standard.
Pour utiliser une distribution non listee dans le catalogue OVH, il faut
uploader son propre qcow2 via OpenStack Glance.

## Catalogue OVH standard

Distributions disponibles directement dans `/cloud/project/{sn}/image` :
AlmaLinux 8/9/10, CloudLinux 8/9, Debian 11/12/13, Fedora 40/42/43,
FreeBSD 14.3/15, Rocky Linux 8/9/10, Ubuntu 18.04/22.04/24.04/25.04,
Windows Server 2016/2019/2022/2025.

Pas de SUSE en standard.

## Workflow BYOI

### Etape 1 : Creer un user OpenStack avec le role image_operator

```bash
# Via l'API OVH
curl -X POST "https://${OVH_ENDPOINT}/1.0/cloud/project/${SERVICE_NAME}/user" \
  -H "..." \
  -d '{"description":"image-uploader","role":"image_operator"}'
```

Le password n'est affiche **qu'une seule fois** dans la reponse.
Il peut etre regenere ensuite via :

```bash
POST /cloud/project/{sn}/user/{userId}/regeneratePassword
```

### Etape 2 : Configurer l'environnement OpenStack

```bash
export OS_AUTH_URL="https://auth.cloud.ovh.net/v3"
export OS_USERNAME="user-XXXXXXXX"
export OS_PASSWORD="..."
export OS_PROJECT_ID="${SERVICE_NAME}"
export OS_REGION_NAME="EU-WEST-PAR"
export OS_USER_DOMAIN_NAME="Default"
export OS_IDENTITY_API_VERSION=3
export OS_INTERFACE=public
```

### Etape 3 : Telecharger l'image qcow2

Sources officielles :

| Distribution | URL |
|--------------|-----|
| openSUSE Leap 15.6 | https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-Minimal-VM.x86_64-Cloud.qcow2 |
| openSUSE MicroOS | https://download.opensuse.org/tumbleweed/appliances/openSUSE-MicroOS.x86_64-OpenStack-Cloud.qcow2 |
| SLES 15 SP6 | https://www.suse.com/download/sles/ (login SCC requis) |

```bash
curl -sLo openSUSE-Leap-15.6.qcow2 \
  "https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-Minimal-VM.x86_64-Cloud.qcow2"
```

### Etape 4 : Upload via openstack CLI

```bash
pip install --user python-openstackclient

openstack image create "openSUSE-Leap-15.6" \
  --file openSUSE-Leap-15.6.qcow2 \
  --disk-format qcow2 \
  --container-format bare \
  --private \
  --property os_distro=opensuse \
  --property os_version=15.6 \
  --property hw_qemu_guest_agent=yes
```

L'upload prend quelques minutes (taille de l'image + bande passante).

### Etape 5 : Utiliser dans OVHMachine

L'image apparait dans `/cloud/project/{sn}/snapshot` (pas dans `/image`).
CAPIOVH la trouve automatiquement :

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha1
kind: OVHMachine
metadata:
  name: my-suse-vm
spec:
  flavorName: b3-16
  imageName: "openSUSE-Leap-15.6"   # nom exact tel qu'uploade
  sshKeyName: my-ssh-key
```

Alternative : utiliser directement l'UUID renvoye par `openstack image create` :

```yaml
spec:
  imageName: "865193d1-cd97-445c-ade9-ac9981fd1cbe"  # UUID, pas de lookup
```

## Resolution d'image dans CAPIOVH

`GetImageByName` du client OVH applique cette logique :

1. Si le nom est un UUID -> utilise tel quel
2. Sinon : recherche dans `/image` (catalogue public OVH)
3. Si pas trouve : recherche dans `/snapshot` (BYOI prive)
4. Match : exact d'abord, puis partial (case-insensitive)

L'utilisateur final n'a donc pas a se soucier de la source de l'image.
