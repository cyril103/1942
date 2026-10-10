extends RefCounted
## Membership is immutable: retiring/escaping a member can never count as a kill.
signal cleared(at: Vector3, bonus: int, red: bool)
var groups: Dictionary = {}
var members: Dictionary = {}
var serial := 0

func begin(count: int, red := false) -> int:
	serial += 1
	groups[serial] = {"remaining": count, "kills": 0, "total": count, "red": red}
	return serial

func register(actor: Node, group: int) -> void:
	var id := actor.get_instance_id()
	members[id] = group
	actor.connect("destroyed",_destroyed.bind(id))
	actor.tree_exiting.connect(_escaped.bind(id), CONNECT_ONE_SHOT)

func _destroyed(at: Vector3, id: int) -> void:
	_resolve(id, true, at)

func _escaped(id: int) -> void:
	_resolve(id, false, Vector3.ZERO)

func _resolve(id: int, killed: bool, at: Vector3) -> void:
	if not members.has(id): return
	var group_id: int = members[id]
	members.erase(id)
	if not groups.has(group_id): return
	var group: Dictionary = groups[group_id]
	group.remaining -= 1
	if killed: group.kills += 1
	if group.remaining > 0: return
	groups.erase(group_id)
	if group.kills == group.total and group.total > 0:
		cleared.emit(at, int(group.total) * (200 if group.red else 100), bool(group.red))

func reset() -> void:
	groups.clear()
	members.clear()
