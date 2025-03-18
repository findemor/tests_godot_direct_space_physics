extends Node2D


@export var origin_area_2d:Node2D
@onready var target_container: Node2D = $TargetContainer
@export var sweeper_speed:float = 100

@export var sweeper:Sweeper
@onready var character_body_2d: CharacterBody2D = $CharacterBody2D


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		sweeper.transfer_as_nodes(target_container, true)
		#transfer(origin_area_2d, sweeper.global_position)
	if event.is_action_pressed("ui_up"):
		origin_area_2d.rotation_degrees += 10
		
func _physics_process(delta: float) -> void:
	if Engine.get_physics_frames() % 30 == 0:
		transfer(origin_area_2d, character_body_2d.global_position)
		
	if Input.is_action_pressed("ui_left"):
		character_body_2d.position += Vector2.LEFT * sweeper_speed * delta
	if Input.is_action_pressed("ui_right"):
		character_body_2d.position += Vector2.RIGHT * sweeper_speed * delta


	
	

## Transfiere los shapes de un nodo a otro, creando CollisionShapes2D como nodos para conenerlos
## origin_container es el nodo del que se obtendrán los shapes de referencia, no se modifica
## reubication_position ignorará la posición del transform de origen y usará esta en su lugar. Vector2.INF usará la de origen
func transfer(origin_container:Node2D, reubication_position:Vector2 = Vector2.INF):
	
	## obtenemos todas las shapes que contiene el nodo de origen
	var all_shapes:Array[Sweeper.ShapeData] = Sweeper.get_all_shapes(origin_container, reubication_position)

	sweeper.initialize(get_world_2d().direct_space_state, all_shapes )
	var sr:Vector2 = sweeper.sweep(character_body_2d.global_position, Vector2.DOWN * 500, [character_body_2d.get_rid()])

	origin_container.global_position = sr
	
	prints("collision at start",sweeper.intersects(target_container.global_position)  ,"collision at end", sweeper.intersects(sr), "FPS", Engine.get_frames_per_second())
	
	## creamos los nuevos nodos asignandole sus propiedades
	#for sr in all_shapes:
		#var new_polygon:CollisionShape2D = CollisionShape2D.new()
		#new_polygon.shape = sr.shape
		#
		#var container_global_xform:Transform2D = origin_container.global_transform
		#if reubication_position != Vector2.INF: container_global_xform.origin = reubication_position
		#var global_xform:Transform2D = container_global_xform * sr.owner_local_transform
		#
		#new_polygon.global_transform = global_xform
		#
		#
		#target_container.add_child(new_polygon)
		
