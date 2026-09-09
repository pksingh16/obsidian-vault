# Linux set no password sudo, create user group & add user to user group

```bash
sed -i 's/^\(%wheel ALL=(ALL:ALL) PASSWD: ALL\)/#/' /etc/sudoers && \
sleep 0.5 && \
sed -i '/^root ALL=(ALL:ALL) ALL$/ { N; /
ansible ALL=(ALL) NOPASSWD: ALL$/!s/
/
ansible ALL=(ALL) NOPASSWD: ALL
/; P; D }' /etc/sudoers && \
sleep 0.5 && \
groupadd ansible && \
sleep 0.5 && \
usermod -aG ansible ansible && \
passwd
```
