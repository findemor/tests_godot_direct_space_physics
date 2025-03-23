extends Node2D


@export var shapes_structure:Node2D ## contiene las formas y poligonos que se tratarán de recolocar
@export var sweeper:Sweeper ## referencia al sweeper que se usará
@export var sweeper_speed:float = 100 ## velocidad de movimiento del personaje con los cursores
@export var search_secondary_lower_position:bool = true ## activa o desactiva la búsqueda de la segunda forma en la posicón baja (agujeros)

@onready var character_body_2d: CharacterBody2D = $CharacterBody2D ## personaje (el cursor que movemos)
@onready var center_ray_cast:RayCast2D = $CharacterBody2D/CenterRayCast2D ## raycast central
@onready var right_ray_cast:RayCast2D = $CharacterBody2D/RightRayCast2D ## raycast derecho

var lower_shadow_container:Node2D ## variable que almacena la estructura duplicada para visualizar la posición secundaria en la que se puede colocar

func _ready() -> void:
	## solo para depuración visual: duplicamos el que usaremos para visualizar la ubicación de la forma secundaria
	if lower_shadow_container != null: lower_shadow_container.queue_free()
	lower_shadow_container = shapes_structure.duplicate()
	lower_shadow_container.modulate.a = 0.3
	add_child(lower_shadow_container)
	
	## actualizamos los datos internos del sweeper
	update_sweeper_data(shapes_structure)

func _input(event: InputEvent) -> void:		
	if event.is_action_pressed("rotate"):
		shapes_structure.rotation_degrees += 10 ## rotamos la estructura
		update_sweeper_data(shapes_structure) ## actualizamos el calculo de las key_positions de la estructura
		
		## opcional, solo para depuracion visual, rotamos la copia que se usa para ver la posición secundaria		
		lower_shadow_container.rotation_degrees = shapes_structure.rotation_degrees ## replica la rotacion simplemente para visualizarlo
		
func _physics_process(delta: float) -> void:
	## obtenemos los puntos de colisión de los raycast
	var center_collision:Vector2 = center_ray_cast.global_position + center_ray_cast.target_position
	if center_ray_cast.is_colliding(): center_collision = center_ray_cast.get_collision_point() 
	
	var right_collision:Vector2 = right_ray_cast.global_position + right_ray_cast.target_position
	if right_ray_cast.is_colliding(): right_collision = right_ray_cast.get_collision_point() 
		
	## obtenemos la posición más baja centrado en el mismo x que la central
	var lower_collision:Vector2 = center_collision if center_collision.y >= right_collision.y else Vector2(center_collision.x, right_collision.y)
	
	## movemos los indicadores visuales de contacto de los raycast
	$VisualDebugMarkers/CenterCollision.global_position = center_collision
	$VisualDebugMarkers/RightCollision.global_position = right_collision
	
	
	## calculamos las posiciones libres de caida	
	if Engine.get_physics_frames() % 30 == 0:
		var start_time = Time.get_ticks_usec()
		
		## primero la posicion principal, desde el origen del raycast hasta el primer contacto (si la pieza cae, donde se para?)
		var center_global_position:Vector2 = sweep_and_reubicate(shapes_structure, center_ray_cast.global_position)
		
		if search_secondary_lower_position:
			## luego la posición alternativa, usando como apoyo la colisión de raycast más baja encontrada... ¿habría sitio para colocarla?
			const CENTER_GLOBAL_POSITION_BELOW_PIXELS:float = 5 ## pixeles por debajo de la posición anterior que se colocará. Esta diferencia hace que ambas formas nunca indiquen el mismo hueco.
			var center_top_y_boundary:float = center_ray_cast.global_position.y if center_global_position == Vector2.INF else center_global_position.y ##cogemos la posicion más álta en la que podria emplazarse
			scan_in_hole_and_reubicate(shapes_structure, lower_collision, center_top_y_boundary + CENTER_GLOBAL_POSITION_BELOW_PIXELS)
		
		var end_time = Time.get_ticks_usec()
	
		prints("FPS", Engine.get_frames_per_second(), "Took: ", (end_time - start_time) / 1000.0, "ms", "center pos", shapes_structure.global_position, "lower pos", lower_shadow_container.global_position)
		
	## movimiento basico del personaje
	if Input.is_action_pressed("ui_left"):
		character_body_2d.position += Vector2.LEFT * sweeper_speed * delta
	if Input.is_action_pressed("ui_right"):
		character_body_2d.position += Vector2.RIGHT * sweeper_speed * delta
	if Input.is_action_pressed("ui_down"):
		character_body_2d.position += Vector2.DOWN * sweeper_speed * delta
	if Input.is_action_pressed("ui_up"):
		character_body_2d.position += Vector2.UP * sweeper_speed * delta


## actualiza la información interna del sweeper para preparlo para el trabajo 
func update_sweeper_data(origin_container:Node2D):
	## obtenemos todas las shapes que contiene el nodo de origen
	var all_shapes:Array[Sweeper.ShapeData] = Sweeper.get_all_shapes(origin_container)
	sweeper.initialize(get_world_2d().direct_space_state, all_shapes )
	sweeper.calculate_key_positions(origin_container)

## escanea verticalmente una posición valida para la estructura, desde la posicion lower_collision, hasta que la estructura llegue a la posicion limite indicada
func scan_in_hole_and_reubicate(origin_container:Node2D, lower_collision:Vector2, center_top_y_boundary:float):
	## reubicatá el contenedor para visualizar la posicion de la estrcutrua, asi que si no existe, detenemos
	if lower_shadow_container == null: return 
	
	var lower_empty_position:Vector2 = sweeper.scan_inside_hole(lower_collision, center_top_y_boundary, [character_body_2d.get_rid()])# + Vector2.DOWN) ## bajamos un pixel para asegurarnos de que nunca están en la misma posición exacta
	
	if lower_empty_position != Vector2.INF:
		## se identifico una posición valida
		lower_shadow_container.visible = true
		lower_shadow_container.global_position = lower_empty_position
		return
	
	## en otro caso no aplica
	lower_shadow_container.visible = false


## reubica origin_container en la posición de primera colision, si dejasemos caer la estructura que contien desde la posición sweep_origin
## origin_container es el nodo que se reubicará
## sweep_origin es la posicion de inicio del sweep, en coodenadas globales
func sweep_and_reubicate(origin_container:Node2D, sweep_origin:Vector2) -> Vector2:
	## calculamos la posición máxima a la que podria caer hasta colisionar, excluimos el character body para evitar que se detenga al solaparse con el al inicio
	var sr:Vector2 = sweeper.sweep(sweep_origin, center_ray_cast.target_position, [character_body_2d.get_rid()])
	
	if sr == Vector2.INF:
		## no se encontró una posición valida
		origin_container.global_position = sweep_origin
	else:
		origin_container.global_position = sr
		
	var offset:Vector2 = origin_container.global_position - sweeper.key_positions.center
	$VisualDebugMarkers/CenterMarker.global_position = sweeper.key_positions.center_point_lowest + offset
	$VisualDebugMarkers/BotMarkerBot.global_position = sweeper.key_positions.lowest_point + offset
	$VisualDebugMarkers/TopMarkerTop.global_position = sweeper.key_positions.highest_point + offset
	$VisualDebugMarkers/BotMarkerTop.global_position = sweeper.key_positions.lowest_point_antipodal + offset
	$VisualDebugMarkers/TopMarkerBot.global_position = sweeper.key_positions.highest_point_antipodal + offset

	return sr
	
