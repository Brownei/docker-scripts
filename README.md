# Tony Teaches Tech VPS Scripts (Brownei's Version)

These scripts are used at Tony Teaches Tech[https://www.youtube.com/channel/UCWPJwoVXJhv0-ucr3pUs1dA] youtube. I just took the boilerplate and made it work for my debian LXC machines

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
