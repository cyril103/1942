extends RefCounted
## Original event signatures, built offline by audio/build_event_signatures.py.
## Immutable shared resources: no synthesis or allocation on the combat thread.
const STREAMS := {
	"boss": preload("res://assets/campaign/audio/events/boss.wav"),
	"danger": preload("res://assets/campaign/audio/events/danger.wav"),
	"radio": preload("res://assets/campaign/audio/events/radio.wav"),
	"radio_important": preload("res://assets/campaign/audio/events/radio_important.wav"),
	"reward": preload("res://assets/campaign/audio/events/reward.wav")
}

static func stream(kind: String) -> AudioStreamWAV:
	return STREAMS.get(kind, STREAMS.radio)
