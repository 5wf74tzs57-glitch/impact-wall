extends Node
## Global hit channel, registered as the "HitBus" autoload.
##
## Every hit source sends its hits here, and games only ever listen here.
## That way a game never knows (or cares) whether a hit came from a tap,
## a replay file or the real hub.

## Emitted once for every hit, from any source.
signal hit(event: HitEvent)


func emit_hit(event: HitEvent) -> void:
	hit.emit(event)
