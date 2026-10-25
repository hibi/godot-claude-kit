extends Node

## Autoload. Exists in the demo so scripts can depend on a singleton - which is what makes
## `--check-only --script` report a false "Identifier not found: GameState".

signal score_changed(score: int)

var score := 0


func add_score(points: int) -> void:
	score += points
	score_changed.emit(score)


func reset() -> void:
	score = 0
