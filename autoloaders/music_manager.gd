extends Node

const ENDLESS_CYBER_RUNNER = preload("uid://bftijdbel4rky")
const S_31_NIGHT_PROWLER = preload("uid://dnqcyxik03jre")
const S_31_SEWER_NIGHTCLUB = preload("uid://dibuo0nbxrsy5")
const SORROW_RUNNER = preload("uid://cv50pn6vbmr7k")

@onready var main_audio_stream_player: AudioStreamPlayer = $MainAudioStreamPlayer
@onready var secondary_audio_stream_player: AudioStreamPlayer = $SecondaryAudioStreamPlayer

func _ready() -> void:
	pass

func play_01(_fade_time: float = 1.0) -> void:
	if main_audio_stream_player:
		main_audio_stream_player.stream = ENDLESS_CYBER_RUNNER
		
		main_audio_stream_player.play()
#
#func play(stream: AudioStream, fade_time: float = 1.0) -> void:
	##ENDLESS_CYBER_RUNNER.get_instance_id()
	#pass
#
#func stop() -> void:
	#pass
#
#func crossfade_to(stream: AudioStream, fade_time: float = 1.5) -> void:
	#pass
#
#func fade_out(fade_time: float = 1.0) -> void:
	#pass
