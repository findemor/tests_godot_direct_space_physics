extends Node2D


@export var origin_area_2d:Node2D
@export var target_area_2d:Node2D
@export var reubication_marker_2d: Marker2D


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		var reubication_global_position:Vector2 = Vector2.INF if reubication_marker_2d == null else reubication_marker_2d.global_position
		transfer(origin_area_2d, target_area_2d, true, reubication_global_position)
	if event.is_action_pressed("ui_up"):
		origin_area_2d.rotation_degrees += 10
	if event.is_action_pressed("ui_right"):
		origin_area_2d.position += Vector2.RIGHT * 20

## Transfiere los shapes de un nodo a otro, creando CollisionShapes2D como nodos para conenerlos
## origin_container es el nodo del que se obtendrán los shapes de referencia, no se modifica
## target_container es el nodo en el que se crearán las nuevas colisiones
## clear_existing elimina todos los nodos hijos del target_container antes de la operación
## reubication_position ignorará la posición del transform de origen y usará esta en su lugar. Vector2.INF usará la de origen
func transfer(origin_container:Node2D, target_container:Node2D, clear_existing:bool, reubication_position:Vector2 = Vector2.INF):
	## elimina los nodos que existen en el contenedor de destino
	if clear_existing:
		for child in target_container.get_children():
			child.queue_free()
	
	## obtenemos todas las shapes que contiene el nodo de origen
	var all_shapes:Array[ShapeReturned] = get_all_shapes(origin_container)
	
	## creamos los nuevos nodos asignandole sus propiedades
	for sr in all_shapes:
		var new_polygon:CollisionShape2D = CollisionShape2D.new()
		new_polygon.shape = sr.shape

		#var container_global_xform:Transform2D = origin_container.global_transform
		#if reubication_position != Vector2.INF: container_global_xform.origin = reubication_position
		#var global_xform:Transform2D = container_global_xform * sr.owner_local_transform
		#new_polygon.global_transform = global_xform
		
		var container_global_xform:Transform2D = sr.owner_global_transform
		container_global_xform.origin = sr.owner_global_transform.origin + Vector2(300, 300) - origin_area_2d.global_position
		new_polygon.global_transform = container_global_xform#global_xform
		
		target_container.add_child(new_polygon)
		
class ShapeReturned:
	var shape:Shape2D
	var owner_global_transform:Transform2D
	var owner_local_transform:Transform2D
	
## obtiene la lista de todas las shapes de los CollisionPolygon2D o CollisionShape2D anidados en Nodo
## si alguno de los poligonos es concavo, puede dar resultados inesperados
func get_all_shapes(container:Node2D) -> Array[ShapeReturned]:
	var shapes:Array[ShapeReturned] = []  # Lista para almacenar todas las shapes
	
	for child:Node2D in container.get_children():		
		if child is CollisionPolygon2D or (child is CollisionShape2D and child.shape):
			
			var shape_returned:ShapeReturned = ShapeReturned.new()
			shape_returned.owner_global_transform = child.global_transform
			shape_returned.owner_local_transform = child.transform
			
			if child is CollisionPolygon2D:
				# Convertir el polígono en una shape y agregarla a la lista
				var shape:ConvexPolygonShape2D = ConvexPolygonShape2D.new()
				shape.points = child.polygon  # Asignar puntos del polígono
				shape_returned.shape = shape
			else:
				# Si es CollisionShape2D, simplemente agregar su shape
				shape_returned.shape = child.shape
				
			shapes.append(shape_returned)

	return shapes

#
#
#
#
#var space_state = get_world_2d().direct_space_state
#var motion = Vector2(100, 0)  # Vector de movimiento
#
#for shape_owner_id in $CollisionShapeContainer.get_shape_owners():
	#var shape = $CollisionShapeContainer.shape_owner_get_shape(shape_owner_id, 0)
	#
	#if shape:
		## Obtener la transformación global de la shape
		#var shape_transform = $CollisionShapeContainer.shape_owner_get_transform(shape_owner_id)
		#var global_shape_transform = global_transform * shape_transform  # Aplicar la rotación y traslación del Area2D
#
		#var motion_params = PhysicsTestMotionParameters2D.new()
		#motion_params.from = global_shape_transform  # Asignamos la posición y rotación global
		#motion_params.motion = motion
		#motion_params.shape_rid = shape.get_rid()
#
		#var motion_result = PhysicsTestMotionResult2D.new()
		#var has_collision = space_state.test_motion(motion_params, motion_result)
#
		#if has_collision:
			#print("Colisión detectada con: ", motion_result.get_collider())
