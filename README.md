# Amnezia Utils

## Amnezia Backup Tool

Backs up and restores your Amnezia VPN containers.

### What it does

- Creates backup of users with date/time stamps
- Can restore from backups when needed

### How to use

#### Make a backup
```bash
./backup.sh
```

#### Restore from backup  
```bash
./backup.sh -r
```

### What you need

- Docker running on your system
- This script file
- Enough disk space for backups

### Where backups go

Backups are saved in a directory `./amnezia-opt-backups/`

### Important

- Restoring will restart your containers
- Test restores carefully 
- Keep your backups safe

## License

Free to use under GPL v3.0 license.
