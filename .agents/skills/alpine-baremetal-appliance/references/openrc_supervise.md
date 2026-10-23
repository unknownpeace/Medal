# OpenRC supervise-daemon Architecture Reference

Alpine Linux utilizes OpenRC with `supervise-daemon` to manage long-running daemon processes natively without systemd or container overhead.

## Anatomy of an OpenRC Runscript
File: `/etc/init.d/caddy`
```sh
#!/sbin/openrc-run
supervisor=supervise-daemon

name="Caddy web server"
command=/usr/sbin/caddy
command_args="run --config /etc/caddy/Caddyfile --adapter caddyfile"
command_user=caddy:caddy
capabilities="^cap_net_bind_service"

depend() {
    need net localmount
    after firewall
}
```

## Logging Configuration
In `/etc/conf.d/<service>`:
```sh
output_log="/var/log/caddy.log"
error_log="/var/log/caddy.log"
```

## Managing Services
```bash
rc-service <service> status
rc-service <service> restart
rc-service <service> stop
rc-update add <service> default
```
