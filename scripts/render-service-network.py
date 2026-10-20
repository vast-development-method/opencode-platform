#!/usr/bin/env python3
"""Validate explicit IPv4 service routes and render a native Incus ACL."""
import ipaddress
import json
import re
import sys


def address(value):
    if not isinstance(value, str):
        raise ValueError("addresses must be IPv4 literals")
    ip = ipaddress.IPv4Address(value)
    forbidden = ("0.0.0.0/8", "127.0.0.0/8", "169.254.0.0/16", "100.64.0.0/10", "224.0.0.0/3")
    if any(ip in ipaddress.ip_network(network) for network in forbidden):
        raise ValueError("loopback, metadata, shared and special-use addresses are forbidden")
    return f"{ip}/32"


def render(data):
    if not isinstance(data, dict) or set(data) - {"schema", "dns", "services", "ssh_sources"} or data.get("schema") != 1:
        raise ValueError("expected schema 1 with dns, services and optional ssh_sources")
    dns = data.get("dns")
    services = data.get("services")
    ssh_sources = data.get("ssh_sources", [])
    if not isinstance(dns, list) or not 1 <= len(dns) <= 4:
        raise ValueError("provide one to four exact DNS addresses")
    if not isinstance(services, list) or not 1 <= len(services) <= 64:
        raise ValueError("provide one to 64 exact service endpoints")
    if not isinstance(ssh_sources, list) or len(ssh_sources) > 16:
        raise ValueError("at most 16 exact SSH source addresses are accepted")
    egress = []
    names = set()
    for ip in dns:
        for protocol in ("tcp", "udp"):
            egress.append(dict(action="allow", state="enabled", description="Approved DNS", destination=address(ip), protocol=protocol, destination_port="53"))
    for service in services:
        if not isinstance(service, dict) or set(service) != {"name", "address", "port"}:
            raise ValueError("each service requires name, address and port")
        name = service["name"]
        port = service["port"]
        if not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9_-]{0,62}", name) or name in names:
            raise ValueError("service names must be unique lowercase identifiers")
        names.add(name)
        if type(port) is not int or not 1 <= port <= 65535:
            raise ValueError("service ports must be integers between 1 and 65535")
        egress.append(dict(action="allow", state="enabled", description=name, destination=address(service["address"]), protocol="tcp", destination_port=str(port)))
    ingress = [dict(action="allow", state="enabled", description="Approved worker SSH", source=address(ip), protocol="tcp", destination_port="22") for ip in ssh_sources]
    return dict(description="Explicit worker service routes", config={"user.vdm.managed": "true", "user.vdm.platform": "vdm-opencode-platform"}, ingress=ingress, egress=egress)


def main():
    try:
        if len(sys.argv) != 2:
            raise ValueError("usage: render-service-network.py CONFIG_JSON")
        with open(sys.argv[1], encoding="utf-8") as source:
            data = json.load(source)
        print(json.dumps(render(data), sort_keys=True, indent=2))
    except (ValueError, OSError) as error:
        print(f"Service network configuration: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
