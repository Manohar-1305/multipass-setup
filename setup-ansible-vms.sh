#!/usr/bin/env bash
set -euo pipefail

cat > ansible-controller-cloud-init.yaml <<'CLOUD'
#cloud-config
package_update: true
packages:
  - ansible
  - openssh-client
  - python3
runcmd:
  - [bash, -lc, "install -d -m 700 -o ubuntu -g ubuntu /home/ubuntu/.ssh"]
  - [bash, -lc, "sudo -u ubuntu ssh-keygen -q -t ed25519 -N '' -f /home/ubuntu/.ssh/id_ed25519"]
CLOUD

cat > ansible-client-cloud-init.yaml <<'CLOUD'
#cloud-config
package_update: true
packages:
  - openssh-server
  - python3
  - sudo
runcmd:
  - [systemctl, enable, --now, ssh]
  - [bash, -lc, "install -d -m 700 -o ubuntu -g ubuntu /home/ubuntu/.ssh"]
CLOUD

multipass launch 24.04 --name ansible-controller --cpus 1 --memory 1G --disk 5G --cloud-init ansible-controller-cloud-init.yaml
multipass launch 24.04 --name ansible-client --cpus 1 --memory 1G --disk 5G --cloud-init ansible-client-cloud-init.yaml

until multipass exec ansible-controller -- cloud-init status --wait >/dev/null 2>&1 &&
      multipass exec ansible-client -- cloud-init status --wait >/dev/null 2>&1; do
  sleep 2
done

PUBKEY=$(multipass exec ansible-controller -- sudo -u ubuntu cat /home/ubuntu/.ssh/id_ed25519.pub)

multipass exec ansible-client -- sudo bash -c \
  "printf '%s\n' '$PUBKEY' >> /home/ubuntu/.ssh/authorized_keys &&
   chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys &&
   chmod 600 /home/ubuntu/.ssh/authorized_keys"

CLIENT_IP=$(multipass info ansible-client | awk '/IPv4:/ {print $2; exit}')

multipass exec ansible-controller -- sudo -u ubuntu bash -c \
  "printf '[clients]\nansible-client ansible_host=$CLIENT_IP ansible_user=ubuntu\n' > /home/ubuntu/inventory &&
   printf '[defaults]\nhost_key_checking = False\n' > /home/ubuntu/ansible.cfg"

multipass exec ansible-controller -- sudo -u ubuntu ansible \
  -i /home/ubuntu/inventory clients -m ping
