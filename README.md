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

### Latest Version

```bash
wget https://raw.githubusercontent.com/tonyflo/ttt-vps-scripts/main/setup.sh
chmod +x setup.sh
sudo ./setup.sh
```
