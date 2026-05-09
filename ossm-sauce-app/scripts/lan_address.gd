class_name LanAddress
extends RefCounted


# Substring patterns (case-insensitive) used to recognize non-LAN adapters —
# WSL/Hyper-V virtual switches, VM host networks, named VPN tunnels,
# container bridges, etc. Matched against both the `friendly` and `name`
# fields of IP.get_local_interfaces() so we cover Windows (friendly="Wi-Fi",
# name=GUID) and Linux/macOS (name="wlan0"/"docker0") with one list.
#
# Patterns are intentionally brand/name-anchored — generic terms like "tun"
# or "tap" risk false positives on real adapters. Unnamed VPN tunnels are
# deprioritized by the LAN-prefix sort in get_primary().
const _VIRTUAL_ADAPTER_PATTERNS := [
	# Linux virtual / WSL / Hyper-V
	"veth", "wsl", "hyper-v", "default switch",
	# Desktop VM software
	"virtualbox", "vbox", "vmware", "parallels",
	# Mesh / overlay networks
	"tailscale", "zerotier", "wireguard", "openvpn",
	"cloudflare", "netbird", "twingate",
	# Consumer VPN brands
	"mullvad", "proton", "nordlynx",
	"expressvpn", "surfshark", "cyberghost", "ipvanish",
	# Container bridges / loopback / Bluetooth PAN
	"docker", "loopback", "bluetooth",
]


static func get_primary() -> String:
	# Two-stage filter: drop interfaces whose friendly/name matches a known
	# virtual-adapter pattern, then within remaining real interfaces apply
	# the LAN-prefix priority below. Falls back to the unfiltered set if
	# filtering leaves nothing — better to surface a wrong-but-real address
	# than blank out entirely.
	var ifaces := IP.get_local_interfaces()
	var real_ifaces: Array = []
	for iface in ifaces:
		if not _is_virtual_interface(iface):
			real_ifaces.append(iface)
	# Priority: real LAN ranges first, virtual-adapter-prone ranges last
	# 192.168.x.x — typical home router
	# 10.x.x.x    — corporate/hotspot LANs, or VPN tunnels
	# 172.16-31   — usually WSL/Docker/Hyper-V virtual switches
	for prefix in ["192.168.", "10.", "172."]:
		for iface in real_ifaces:
			for addr in iface.get("addresses", []):
				if _is_usable_lan_ipv4(addr) and addr.begins_with(prefix):
					return addr
	for prefix in ["192.168.", "10.", "172."]:
		for iface in ifaces:
			for addr in iface.get("addresses", []):
				if _is_usable_lan_ipv4(addr) and addr.begins_with(prefix):
					return addr
	return "No LAN IP found"


static func get_candidate_list() -> String:
	# Builds a sorted multi-line list of all reachable IPv4 candidates for the
	# IP picker fallback. Virtual adapters are NOT excluded — the picker exists
	# because auto-detection may have chosen wrong, and the user needs every
	# option visible to override. IPv6, loopback, and APIPA are dropped since
	# they're never the correct answer for OSSM connectivity.
	var auto_pick := get_primary()
	var entries: Array = []  # [prefix_rank, virtual_rank, ip, label]
	for iface in IP.get_local_interfaces():
		var friendly: String = str(iface.get("friendly", ""))
		var name: String = str(iface.get("name", ""))
		var label: String
		if friendly != "" and friendly != name:
			label = friendly
		elif name != "":
			label = name
		else:
			label = "(unnamed)"
		var is_virtual := _is_virtual_interface(iface)
		for addr in iface.get("addresses", []):
			if not _is_usable_lan_ipv4(addr):
				continue
			var prefix_rank := 9
			if addr.begins_with("192.168."):
				prefix_rank = 0
			elif addr.begins_with("10."):
				prefix_rank = 1
			elif addr.begins_with("172."):
				prefix_rank = 2
			var virtual_rank := 1 if is_virtual else 0
			entries.append([prefix_rank, virtual_rank, addr, label])
	entries.sort_custom(func(a, b):
		# Auto-pick always first, then prefix priority, virtual demoted, then IP.
		var a_is_auto: bool = a[2] == auto_pick
		var b_is_auto: bool = b[2] == auto_pick
		if a_is_auto != b_is_auto: return a_is_auto
		if a[0] != b[0]: return a[0] < b[0]
		if a[1] != b[1]: return a[1] < b[1]
		return a[2] < b[2])
	if entries.is_empty():
		return "No LAN IP found"
	var lines: PackedStringArray = []
	for i in entries.size():
		var e = entries[i]
		var marker := "> " if e[2] == auto_pick else "  "
		lines.append("%s%s - %s" % [marker, e[2].rpad(15), e[3]] + "\n")
		if i == 0 and entries.size() > 1:
			lines.append("Other possible addresses:" + "\n")
	return "\n".join(lines)


static func _is_virtual_interface(iface: Dictionary) -> bool:
	var friendly: String = str(iface.get("friendly", "")).to_lower()
	var name: String = str(iface.get("name", "")).to_lower()
	var combined := friendly + "\n" + name
	for pattern in _VIRTUAL_ADAPTER_PATTERNS:
		if pattern in combined:
			return true
	return false


static func _is_usable_lan_ipv4(ip: String) -> bool:
	# Reject IPv6, loopback, and APIPA link-local before the RFC1918 check.
	if ":" in ip:
		return false
	if ip.begins_with("127.") or ip.begins_with("169.254."):
		return false
	return _is_private_ip(ip)


static func _is_private_ip(ip: String) -> bool:
	if ip.begins_with("192.168.") or ip.begins_with("10."):
		return true
	if ip.begins_with("172."):
		var second_octet := int(ip.split(".")[1])
		return second_octet >= 16 and second_octet <= 31
	return false
