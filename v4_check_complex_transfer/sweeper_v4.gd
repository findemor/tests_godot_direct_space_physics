class_name Sweeper_v4 extends Polygon2D

## Esta clase hace un motion_cast de una estructura formada por varias formas convexas
## Conserva la posición relativa de cada forma en la estructura y su rotación global,
## pero no la posicion en la escena, que intenta reubicarla en una posición ancla a partir de la cual
## se intenta hacer el motion_cast hasta una posición determinada especificada por el cast_length a partir de ella

const END_MOTION_CONTACT_GUARANTEE_MARGIN:float = 10 ## pixeles que se alarga el motion para asegurar el contacto

@export_flags_2d_physics var collision_mask ## mascara de colisión de los objetos que pueden ser detectados como obstaculos durante el motion_cast
@export var collide_with_areas:bool = false
@export var collide_with_bodies:bool = true

var shapes:Array[ShapeData] = [] ## información sobre las formas que componen la estructura que intentará reposicionarse
var space_state: PhysicsDirectSpaceState2D  ## Espacio de física en el que se realiza la búsqueda

	
## obtiene la lista de todas las shapes de los CollisionPolygon2D o CollisionShape2D anidados en Nodo
## si alguno de los poligonos es concavo, puede dar resultados inesperados
static func get_all_shapes(container:Node2D, anchor_position:Vector2) -> Array[ShapeData]:
	var shapes:Array[ShapeData] = []  # Lista para almacenar todas las shapes
	
	for child:Node2D in container.get_children():		
		if child is CollisionPolygon2D or (child is CollisionShape2D and child.shape):
			
			var shape_returned:ShapeData = ShapeData.new()
			shape_returned.owner_global_transform = child.global_transform
			shape_returned.owner_local_transform = child.transform
			shape_returned.container_global_position = container.global_position
			## transform trasladada al punto deseado
			#shape_returned.anchor_global_transform = child.global_transform
			#shape_returned.anchor_global_transform.origin = child.global_transform.origin - container.global_position + anchor_position
		
		#var container_global_xform:Transform2D = sr.owner_global_transform
		#container_global_xform.origin = sr.owner_global_transform.origin + Vector2(300, 300) - origin_area_2d.global_position
		#new_polygon.global_transform = container_global_xform#global_xform
			
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

## devuelve un porcentaje de 0 a 1 que determina el grado de avance que ha alcanzado una posición en la trayectoria formada por los puntos de origen y destino
static func distance_pct(origin: Vector2, target: Vector2, pos: Vector2) -> float:
	var target_distance:float = origin.distance_to(target)
	
	# Evitar divisiones por cero si el origen y destino son el mismo punto
	if target_distance == 0:
		return 0.0
	
	var pos_distance:float = origin.distance_to(pos)
	return clamp(pos_distance / target_distance, 0.0, 1.0)

## configura el Sweeper antes de hacer el sweep
func initialize(physics_direct_space_state: PhysicsDirectSpaceState2D, shapes_structure:Array[ShapeData]) -> void:
	space_state = physics_direct_space_state
	shapes = shapes_structure

## Devuelve la posición en la que podría instanciarse la estructura sin colision de ninguna de las formas que la forman
## Mantiene la posición relativa de las formas entre si, y su rotación global, pero reposicionando la estructura en origin_position
## Vector2.ZERO significa que no se encontró ninguna posición valida
func sweep(origin_position:Vector2, cast_length:Vector2, excluded_rids:Array[RID] = []) -> Vector2:
	var free_position:Vector2 = Vector2.ZERO

	## resultado máximo y minimo para cualquiera de las formas que componen la figura	
	var motion_min:SweepingResult = null
	var motion_max:SweepingResult = null
	
	var sweeping_result:SweepingResult = null
	for shape in shapes:
		sweeping_result = _sweep(shape, cast_length, origin_position, excluded_rids)
		if sweeping_result != null:
			## observamos si los valores de desplazamiento máximo o minimo deben recalcularse para alguna de las formas
			if motion_min == null: motion_min = sweeping_result
			if motion_max == null: motion_max = sweeping_result
			if sweeping_result.motion_pct < motion_min.motion_pct: motion_min = sweeping_result
			if sweeping_result.motion_pct > motion_max.motion_pct: motion_max = sweeping_result

	if motion_min != null:
		## la posición libre a la que pueden desplazarse todas las piezas sin colision, es la de la que menos ha podido desplazarse antes de colisionar
		free_position = origin_position.lerp(origin_position + cast_length, clamp(motion_min.motion_pct, 0.0, 1.0)) 
	else:
		free_position = Vector2.ZERO
		
	return free_position ## devuelve la posición libre en la que las formas pueden colocarse sin colisión

## comprueba si existe alguna colisión de la estructura reubicada en la posición especificada
func intersects(anchor_global_position:Vector2, excluded_rids:Array[RID] = []) -> bool:
	for shape in shapes:
		if _shape_intersects(shape, anchor_global_position, excluded_rids):
			return true
	return false
	
## crea dentro del target container nuevos nodos collisionshapes2D
## aplicando las transformaciones y el punto de anclaje que se hayan calculado
## se utiliza básicamente para depurar visualmente estos calculos internos
func transfer_as_nodes(target_container:Node2D, clear_target_container_children:bool = true):
	if clear_target_container_children:
		## vaciamos el contenedor
		for c in target_container.get_children():
			c.queue_free()
			
	## obtenemos todas las shapes que contiene el nodo de origen
	for sr in shapes:
		var new_polygon:CollisionShape2D = CollisionShape2D.new()
		new_polygon.shape = sr.shape
		new_polygon.global_transform = sr.get_anchor_transform(target_container.global_position)
		
		target_container.add_child(new_polygon)

## prepara la query y devuelve la información de contacto de una forma si avanzase cast_length
func _sweep(shape_data:ShapeData, cast_length:Vector2,\
	cast_origin_global_position:Vector2,\
	excluded_rids:Array[RID] = []):
	
	var query = PhysicsShapeQueryParameters2D.new()
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = collide_with_bodies
	query.collision_mask = collision_mask
	query.motion = cast_length
	query.shape = shape_data.shape
	query.transform = shape_data.get_anchor_transform(cast_origin_global_position)
	query.exclude = excluded_rids #[area_to_place.get_rid()]
	
	return _shape_sweep(query, false)

## devuelve información del punto de contacto de una forma si avanzase en una dirección especificada por la query
## si fast_mode == true, es más rápido pero no devuelve información del punto de contacto ni de la colisión
## si null_when_no_collision == true, devuelve null si no hubo colision. En otro caso devuelve la distancia máxima del cast_motion
func _shape_sweep(query: PhysicsShapeQueryParameters2D, consider_existing_collision:bool = false, null_when_no_collision:bool = false) -> SweepingResult:
	var data = null
	var return_data:SweepingResult = null
	
	if consider_existing_collision:
		# primero comprobamos si ya hay un overlap ya que las colisiones existentes se ignoran según la doc
		data = space_state.get_rest_info(query)
		if not data.is_empty():
			if return_data == null: return_data = SweepingResult.new()
			return_data.contact_point = data.point
			return_data.shape_position = query.transform.origin
			return_data.motion_pct = 0
			#prints("Existing overlap at start")
			return return_data
	
	## realizamos un cast_motion para ver cuanto se podría mover sin colisionar
	var motion = space_state.cast_motion(query)
	var start_pos = query.transform.get_origin()
	#var end_pos = start_pos + query.motion
	if motion[0] == 1:
		#prints("No motion collision detected", motion)
		if null_when_no_collision:
			return_data = null
		else:
			## devolvemos la máxima distancia del motion
			if return_data == null: return_data = SweepingResult.new()
			return_data.shape_position = start_pos + query.motion 
			return_data.contact_point = start_pos + (1 + END_MOTION_CONTACT_GUARANTEE_MARGIN / query.motion.length()) * query.motion
			return_data.motion_pct = 1
			
		return return_data
	else:
		#prints("Motion collision detected", motion)
		if return_data == null: return_data = SweepingResult.new()
		## calculamos las posiciones de contacto entre las que hay espacio libre
		#var unsafe_pos = start_pos + motion[1] * query.motion 
		var safe_pos = start_pos + motion[0] * query.motion 
		var end_contact_point : Vector2
		## estiramos un poco más el punto de contacto en la direccion del movimiento para garantizar que contactamos con lo que se ha detectado
		end_contact_point = start_pos + (motion[0] + END_MOTION_CONTACT_GUARANTEE_MARGIN / query.motion.length()) * query.motion
		
		return_data.contact_point = end_contact_point
		return_data.shape_position = safe_pos
		return_data.motion_pct = motion[0]
		
		return return_data

		

	

## comprueba si existe alguna colisión de la forma reubicada en la posición especificada
func _shape_intersects(shape_data:ShapeData, anchor_global_position:Vector2, excluded_rids:Array[RID] = []) -> bool:
	var query = PhysicsShapeQueryParameters2D.new()
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = collide_with_bodies
	query.collision_mask = collision_mask
	query.shape = shape_data.shape
	query.transform = shape_data.get_anchor_transform(anchor_global_position)
	query.exclude = excluded_rids #[area_to_place.get_rid()]
	
	var data:Array[Dictionary] = space_state.intersect_shape(query)
	if data != null and data.size() > 0:
		return true
	else:
		return false ## no hay collider, no hay colisión
	
## Clase que contiene la información del resultado del calculo del barrido de una forma inddividual
class SweepingResult:
	var contact_point:Vector2 ## punto de contacto más cercano identificado con la forma por la que no puede avanzar el barrido
	var shape_position:Vector2 ## posición donde se debe ubicar la forma para que no colisione con otros objetos
	var motion_pct:float ## porcentaje del movimiento casteado que ha podido desplazarse hasta encontrar una colisión

## Clase que contiene la información para representar una forma individual de las que forman una estructura
class ShapeData:
	var shape:Shape2D ## forma
	var owner_global_transform:Transform2D ## transform global de la forma original
	var owner_local_transform:Transform2D ## transform local de la forma
	var container_global_position:Vector2 ## posición global del contenedor de esta forma (es decir, de la estructura)


	## transform global de la forma pero reubicando la estructura en el punto determinado por el anchor
	func get_anchor_transform(anchor_position:Vector2) -> Transform2D:
		var xform:Transform2D = owner_global_transform
		xform.origin = xform.origin - container_global_position + anchor_position
		return xform
		
	
