# Docker NRPE Container

NRPE (Nagios Remote Plugin Executor) container with additional monitoring plugins. Built on Alpine Linux for minimal footprint and enhanced security.

**Note**: This container is primarily maintained for the author's specific needs and includes several custom monitoring scripts that might not be useful for general purposes. It was originally created in 2017 and has evolved to meet specific monitoring requirements.

## Features

- Based on Alpine Linux for minimal image size
- Includes standard Nagios plugins
- Additional custom checks including Docker, Swarm, backup monitoring, and various system metrics

## Installation

Pull from Docker Hub:
```bash
docker pull mikenowak/nrpe
```

## Usage

### Basic Run Command
```bash
docker run -d --restart unless-stopped \
  -v /:/rootfs:ro \
  -v /var/run:/var/run:rw \
  -v /sys:/sys:ro \
  -v /var/lib/docker/:/var/lib/docker:ro \
  --privileged \
  --net=host \
  --ipc=host \
  --pid=host \
  -e NAGIOS_SERVER="1.2.3.4" \
  mikenowak/nrpe
```

### Required Environment Variables

- `NAGIOS_SERVER`: IP address of your Nagios monitoring server

### Volume Mounts

The container requires several mounts to function properly:
- `/:/rootfs:ro`: Root filesystem (read-only)
- `/var/run:/var/run:rw`: Runtime directory
- `/sys:/sys:ro`: System information
- `/var/lib/docker/:/var/lib/docker:ro`: Docker information (for Docker checks)

### Docker Compose Example

```yaml
version: '3.8'

services:
  nrpe:
    image: mikenowak/nrpe
    environment:
      - NAGIOS_SERVER=1.2.3.4
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    privileged: true
    network_mode: host
    ipc: host
    pid: host
    restart: unless-stopped
```

## Security Considerations

- Container runs with privileged access
- Host network access required
- Root filesystem mounted read-only
- NRPE configured with minimal permissions
- Uses specific user (nagios) for running checks

## Building from Source

```bash
git clone https://github.com/mikenowak/docker-nrpe.git
cd docker-nrpe
docker build -t local/nrpe .
```

## Attributions

This container includes monitoring scripts from various sources:

- check_oxidized: https://github.com/ytti/oxidized
- check_cpu_stats.sh, check_file_count, check_ro_mounts, check_time_skew, check_memory: Originally from Opsview (version unknown)
- check_docker and check_swarm: https://github.com/timdaman/check_docker
- check_backup: Custom script by the container author

Some scripts included in this container come from sources that can no longer be properly attributed due to the age of the project (originally created in 2017). Apologies to the original authors where proper attribution couldn't be maintained.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License

[MIT](LICENSE)
