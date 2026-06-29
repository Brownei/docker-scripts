# Tony Teaches Tech VPS Scripts

Scripts used in my YouTube tutorials.

## Docker VPS Bootstrap Script

Downloads, secures, and prepares a VPS for Docker deployments.
- Initial public release
- Creates non-root user
- Hardens SSH
- Updates system
- Enables unattended upgrades
- Installs Docker
- Configures UFW
- Installs Fail2Ban


### Debain setup config
```bash
wget https://raw.githubusercontent.com/Brownei/docker-scripts/main/setup-docker-debian.sh
```

### Ubuntu setup config
```bash
wget https://raw.githubusercontent.com/Brownei/docker-scripts/main/setup-docker-ubuntu.sh
```

### After script download
```bash
chmod +x setup-docker-[os].sh
sudo ./setup-docker-[os].sh
```

#### > [!NOTE]
> Please run the sudo with the script when using ubuntu
