extends Node2D


@export var origin_area_2d:Node2D
@onready var target_container: Node2D = $TargetContainer
@export var sweeper_speed:float = 100

@export var sweeper:Sweeper
@onready var character_body_2d: CharacterBody2D = $CharacterBody2D

@onready var center_ray_cast:RayCast2D = $CharacterBody2D/CenterRayCast2D
@onready var right_ray_cast:RayCast2D = $CharacterBody2D/RightRayCast2D


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		#sweeper.transfer_as_nodes(target_container, true)
		update_sweeper_data(origin_area_2d)
		#transfer(origin_area_2d, sweeper.global_position)
	if event.is_action_pressed("ui_up"):
		origin_area_2d.rotation_degrees += 10
		update_sweeper_data(origin_area_2d)
		
func _physics_process(delta: float) -> void:
	
	var center_collision:Vector2 = center_ray_cast.global_position + center_ray_cast.target_position
	if center_ray_cast.is_colliding():
		center_collision = center_ray_cast.get_collision_point() 
	
	var right_collision:Vector2 = right_ray_cast.global_position + right_ray_cast.target_position
	if right_ray_cast.is_colliding():
		right_collision = right_ray_cast.get_collision_point() 
		
	## la posición más baja centrado en el mismo x
	var lower_collision:Vector2 = center_collision if center_collision.y >= right_collision.y else Vector2(center_collision.x, right_collision.y)
	
	$CenterCollision.global_position = center_collision
	$RightCollision.global_position = right_collision
	
	
	## ya sabemos los puntos de colision
	
	
	if Engine.get_physics_frames() % 30 == 0:
		sweep_and_reubicate(origin_area_2d, center_ray_cast.global_position)
		
	if Input.is_action_pressed("ui_left"):
		character_body_2d.position += Vector2.LEFT * sweeper_speed * delta
	if Input.is_action_pressed("ui_right"):
		character_body_2d.position += Vector2.RIGHT * sweeper_speed * delta


func update_sweeper_data(origin_container:Node2D):
	## obtenemos todas las shapes que contiene el nodo de origen
	var all_shapes:Array[Sweeper.ShapeData] = Sweeper.get_all_shapes(origin_container)
	sweeper.initialize(get_world_2d().direct_space_state, all_shapes )
	
	sweeper.calculate_key_positions(origin_container)
	$CenterMarker.global_position = sweeper.key_positions.center_point_lowest
	$BotMarkerBot.global_position = sweeper.key_positions.lowest_point
	$TopMarkerTop.global_position = sweeper.key_positions.highest_point
	$BotMarkerTop.global_position = sweeper.key_positions.lowest_point_antipodal
	$TopMarkerBot.global_position = sweeper.key_positions.highest_point_antipodal


## Transfiere los shapes de un nodo a otro, creando CollisionShapes2D como nodos para conenerlos
## origin_container es el nodo del que se obtendrán los shapes de referencia, no se modifica
## sweep_origin es la posicion de inicio del sweep, en coodenadas globales
func sweep_and_reubicate(origin_container:Node2D, sweep_origin:Vector2):
	
	var sr:Vector2 = sweeper.sweep(sweep_origin, center_ray_cast.target_position, [character_body_2d.get_rid()])
	
	if sr == Vector2.INF:
		origin_container.global_position = sweep_origin
	else:
		origin_container.global_position = sr
	prints("collision at start",sweeper.intersects(target_container.global_position)  ,"collision at end", sweeper.intersects(sr), "FPS", Engine.get_frames_per_second())
	## solo para refrescar los marcadores visualmente, esto solo se hace una vez al inicio
	
	sweeper.calculate_key_positions(origin_container)
	$CenterMarker.global_position = sweeper.key_positions.center_point_lowest
	$BotMarkerBot.global_position = sweeper.key_positions.lowest_point
	$TopMarkerTop.global_position = sweeper.key_positions.highest_point
	$BotMarkerTop.global_position = sweeper.key_positions.lowest_point_antipodal
	$TopMarkerBot.global_position = sweeper.key_positions.highest_point_antipodal
	
	

	
#
	#
	#var cast_length:float = 1000
	#
	#var casts_points:Array[Vector2] = [p[3], p[4]] # desde el opuesto a la posicón más baja, hacia abajo, y desde el opuesto de la posición más alta, hacia arriba
	#var casts_directions:Array[Vector2] = [Vector2.DOWN * cast_length, Vector2.UP * cast_length]
	#var c = sweeper.get_ray_intersections(casts_points, casts_directions)
	#$BotCollision.global_position = c[0]
	#$TopCollision.global_position = c[1]
	
	#
	#var data = sweeper.test_rest(all_shapes[0], character_body_2d.global_position, [character_body_2d.get_rid()])
	#
	#all_shapes[0].get_anchor_transform(character_body_2d.global_position)
	#
	#if data != null and data.has("point"):
		#$Polygon2D.global_position = data.point
	#else:
		#$Polygon2D.global_position = Vector2(0, 10)
	
	
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
		
