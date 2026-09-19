extends Node
## Main scene root. Hands control to the Game autoload.


func _ready() -> void:
	Game.boot(self)
