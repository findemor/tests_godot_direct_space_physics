class_name Sweeper extends Node

## Esta clase hace un motion_cast de una estructura formada por varias formas convexas
## Conserva la posición relativa de cada forma en la estructura y su rotación global,
## pero no la posicion en la escena, que intenta reubicarla en una posición ancla a partir de la cual
## se intenta hacer el motion_cast hasta una posición determinada especificada por el cast_length a partir de ella

const END_MOTION_CONTACT_GUARANTEE_MARGIN:float = 10 ## pixeles que se alarga el motion para asegurar el contacto

@export_flags_2d_physics var collision_mask ## mascara de colisión de los objetos que pueden ser detectados como obstaculos durante el motion_cast
@export var collide_with_areas:bool = false
@export var collide_with_bodies:bool = true
@export var collision_margin:float = 0.0

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
	query.margin = collision_margin
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
		#var unsafe_pos = start_pos + motion[1] * query.motion  ##TODO usar esto en lugar de end motion guarantee margin
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
	query.margin = collision_margin
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
		
	
###### pruebas


class ScanQuery:
	var scan_motion:Vector2
	var scan_origin_global_position:Vector2
	var scan_step_pixel:float

	## devuelve una posición de la trayectoria en un paso concreto
	func get_step_position(n_step:int) -> Vector2:
		return scan_origin_global_position + scan_motion.normalized() * scan_step_pixel * n_step

	func get_max_n_step() -> int:
		var distance = scan_motion.length()
		return int(distance / scan_step_pixel)

	func position_exceeds_motion(step_pos:Vector2) -> bool:
		return scan_origin_global_position.distance_to(step_pos) > scan_origin_global_position.distance_to(scan_origin_global_position + scan_motion)





## 
## bottom_pos es la posicion de inicio del escaneo (normalmente la colisión con el suelo, desde donde se tratara de buscar un emplazamiento válido)
## top_pos es la posición más alta en la que se podría emplazar la estructura
func test_scan(bottom_pos:Vector2, top_pos:Vector2):
	## bottom_collision
	## bottom_boundary
	## top_bounday
	pass
	
	
	## buscar bottom_collision_rest_point (el punto de colision con la estructura en bottom_collision.x).
	##   posicionar desplazando la estructura de manera que bottom_collision_rest_point.y == bottom_collision.y
	##   el centro de la estructura en ese punto es A, origen no optimizado de bottom boundary
	##     se puede optimizar calculando el punto sin colisión del vertice más bajo de la estructura, que lo podría elevar más
	##   el punto B, destino no optimizado de top_boundary, se indica por parametro (es la posición de la estructura en el punto central, si es más alto)
	##     se puede optimizar calculando el punto de colisión del vertice más alto, siempre que sea una posición mas baja que la indicada
	
	## una vez que tenemos free boundary, escaneamos verticalmente el intersect shape entre ambos puntos
	## de abajo a arriba hasta que encueentra un lugar en el que emplazarse
	## si un area tiene colisión, se descarta el paso.

## dado una serie de puntos y de longitudes direccionales (casts), devuelve las colisiones obteneidas en cada uno de ellos
func get_ray_intersections(points:Array[Vector2], casts:Array[Vector2]) -> Array[Vector2]:
	var query:PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.new()
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = collide_with_bodies
	query.collision_mask = collision_mask
	#query.hit_from_inside
	
	var collisions:Array[Vector2] = []
	
	for i in range(points.size()):
		query.from = points[i]
		query.to = points[i] + casts[i]
		var data:Dictionary = space_state.intersect_ray(query)
		if data.is_empty():
			## se devuelve el máximo alcance detectado por el raycast sin colision
			collisions.append(query.to)
		else:
			collisions.append(data.position)
	
	return collisions
	
	


## Obtiene los puntos de apoyo más relevantes del nodo, analizando las formas que contiene
## container: nodo que contiene los nodos CollisionPolygon o CollisionShape que se analizarán
## x_target: posición en X en la que se obtendrá la posición de apoyo, es decir, el punto en el que, para esa X, hay un punto más bajo de colisión con cualquiera de las formas. Si no hay colisión, devuelve Vector2.INF
## Retorna un array con tres posiciones:
## [0]: best point, posición de punto más bajo de colisión en x = x_target. Si no hay colisión, devuelve Vector2.INF
## [1]: lowest_point, posición del punto más bajo de la estructura formada por las formas. Es decir, aquel punto en el que la coordenada Y es mayor.
## [2]: highest_point, posición del punto más alto de la estructura formada por las formas. Es decir, aquel punto en el que la coordenada Y es menor.
## [3]: top_in_lowest_x, Punto más alto (Y min.) en la misma X que el más bajo
## [4]: bottom_in_highest_x, Punto más bajo (Y max.) en la misma X que el más alto
func get_rest_positions(container: Node2D, x_target: float) -> Array[Vector2]:
	# -- PRIMER PASO: hallamos lowest_point (Y mayor) y highest_point (Y menor) en todos los nodos --
	var lowest_point = Vector2.INF
	var lowest_y = -INF
	var highest_point = Vector2.INF
	var highest_y = INF

	for child in container.get_children():
		if child is CollisionPolygon2D or (child is CollisionShape2D and child.shape is ConvexPolygonShape2D):
			var polygon = child.polygon if child is CollisionPolygon2D else child.shape.points
			for i in range(polygon.size()):
				var gp = child.global_transform * polygon[i]
				if gp.y > lowest_y:
					lowest_y = gp.y
					lowest_point = gp
				if gp.y < highest_y:
					highest_y = gp.y
					highest_point = gp

		elif child is CollisionShape2D:
			var xf = child.global_transform
			var shape = child.shape

			if shape is RectangleShape2D:
				var ext = shape.size * 0.5
				var rect_points = [
					Vector2(-ext.x, -ext.y),
					Vector2(ext.x, -ext.y),
					Vector2(ext.x,  ext.y),
					Vector2(-ext.x,  ext.y)
				]
				for p in rect_points:
					var gp = xf * p
					if gp.y > lowest_y:
						lowest_y = gp.y
						lowest_point = gp
					if gp.y < highest_y:
						highest_y = gp.y
						highest_point = gp

			elif shape is CircleShape2D:
				var r = shape.radius
				var c = xf.origin
				var bottom = Vector2(c.x, c.y + r)
				var top = Vector2(c.x, c.y - r)
				if bottom.y > lowest_y:
					lowest_y = bottom.y
					lowest_point = bottom
				if top.y < highest_y:
					highest_y = top.y
					highest_point = top

			elif shape is CapsuleShape2D:
				var r = shape.radius
				var half_h = shape.height * 0.5
				var c = xf.origin
				var bottom = Vector2(c.x, c.y + half_h + r)
				var top = Vector2(c.x, c.y - half_h - r)
				if bottom.y > lowest_y:
					lowest_y = bottom.y
					lowest_point = bottom
				if top.y < highest_y:
					highest_y = top.y
					highest_point = top

	# -- SEGUNDO PASO: buscamos (1) intersección máx. en x_target, 
	#                  (2) intersección mín. en x = lowest_point.x
	#                  (3) intersección máx. en x = highest_point.x --
	var best_point = _get_intersection_at_x(container, x_target, true)    # máx. Y
	var top_in_lowest_x = Vector2.INF
	var bottom_in_highest_x = Vector2.INF

	if lowest_point != Vector2.INF:
		# "Punto más alto" en la misma X que el "más bajo" => buscamos intersección mín. Y
		top_in_lowest_x = _get_intersection_at_x(container, lowest_point.x, false)
	if highest_point != Vector2.INF:
		# "Punto más bajo" en la misma X que el "más alto" => buscamos intersección máx. Y
		bottom_in_highest_x = _get_intersection_at_x(container, highest_point.x, true)

	return [
		best_point,        # 0) Intersección en x_target (Y máx.)
		lowest_point,      # 1) Punto global más abajo (Y más grande)
		highest_point,     # 2) Punto global más arriba (Y más pequeño)
		top_in_lowest_x,   # 3) Punto más alto (Y min.) en la misma X que el más bajo
		bottom_in_highest_x# 4) Punto más bajo (Y max.) en la misma X que el más alto
	]


func _get_intersection_at_x(container: Node2D, x_coord: float, want_max_y: bool) -> Vector2:
	# Retorna la intersección con las formas en x_coord. 
	# Si want_max_y = true, busca la Y más grande; si es false, la Y más pequeña.
	var chosen_point = Vector2.INF
	var best_y = -INF if want_max_y else INF

	for child in container.get_children():
		# -- POLÍGONOS (CollisionPolygon2D o ConvexPolygonShape2D) --
		if child is CollisionPolygon2D or (child is CollisionShape2D and child.shape is ConvexPolygonShape2D):
			var polygon = child.polygon if child is CollisionPolygon2D else child.shape.points
			for i in range(polygon.size()):
				var p1 = child.global_transform * polygon[i]
				var p2 = child.global_transform * polygon[(i + 1) % polygon.size()]
				if ((p1.x <= x_coord and x_coord <= p2.x) or (p2.x <= x_coord and x_coord <= p1.x)) and p1.x != p2.x:
					var inter_y = p1.y + (p2.y - p1.y) * ((x_coord - p1.x) / (p2.x - p1.x))
					if want_max_y:
						if inter_y > best_y:
							best_y = inter_y
							chosen_point = Vector2(x_coord, inter_y)
					else:
						if inter_y < best_y:
							best_y = inter_y
							chosen_point = Vector2(x_coord, inter_y)

		# -- COLLISIONSHAPE2D: RECT, CÍRCULO, CÁPSULA --
		elif child is CollisionShape2D:
			var xf = child.global_transform
			var shape = child.shape

			if shape is RectangleShape2D:
				var ext = shape.size * 0.5
				var rect_points = [
					Vector2(-ext.x, -ext.y),
					Vector2(ext.x, -ext.y),
					Vector2(ext.x,  ext.y),
					Vector2(-ext.x,  ext.y)
				]
				for i in range(rect_points.size()):
					var gp1 = xf * rect_points[i]
					var gp2 = xf * rect_points[(i + 1) % rect_points.size()]
					if ((gp1.x <= x_coord and x_coord <= gp2.x) or (gp2.x <= x_coord and x_coord <= gp1.x)) and gp1.x != gp2.x:
						var inter_y = gp1.y + (gp2.y - gp1.y) * ((x_coord - gp1.x) / (gp2.x - gp1.x))
						if want_max_y:
							if inter_y > best_y:
								best_y = inter_y
								chosen_point = Vector2(x_coord, inter_y)
						else:
							if inter_y < best_y:
								best_y = inter_y
								chosen_point = Vector2(x_coord, inter_y)

			elif shape is CircleShape2D:
				var r = shape.radius
				var c = xf.origin
				if abs(c.x - x_coord) <= r:
					# Hay dos posibles intersecciones en esa X, la de arriba y la de abajo
					var dy = sqrt(r * r - pow(x_coord - c.x, 2))
					var y_up = c.y - dy
					var y_down = c.y + dy
					# Según want_max_y, elegimos la más apropiada
					if want_max_y:
						if y_down > best_y:
							best_y = y_down
							chosen_point = Vector2(x_coord, y_down)
						if y_up > best_y:
							best_y = y_up
							chosen_point = Vector2(x_coord, y_up)
					else:
						if y_up < best_y:
							best_y = y_up
							chosen_point = Vector2(x_coord, y_up)
						if y_down < best_y:
							best_y = y_down
							chosen_point = Vector2(x_coord, y_down)

			elif shape is CapsuleShape2D:
				var r = shape.radius
				var half_h = shape.height * 0.5
				var c = xf.origin
				# Para simplificar, chequeamos igual que el círculo, pero el centro "vertical" se desplaza
				# 1) parte circular inferior
				var bottom_center = Vector2(c.x, c.y + half_h)
				if abs(bottom_center.x - x_coord) <= r:
					var dy = sqrt(r*r - pow(x_coord - bottom_center.x, 2))
					var y_up_bottom = bottom_center.y - dy
					var y_down_bottom = bottom_center.y + dy
					if want_max_y:
						if y_down_bottom > best_y:
							best_y = y_down_bottom
							chosen_point = Vector2(x_coord, y_down_bottom)
						if y_up_bottom > best_y:
							best_y = y_up_bottom
							chosen_point = Vector2(x_coord, y_up_bottom)
					else:
						if y_up_bottom < best_y:
							best_y = y_up_bottom
							chosen_point = Vector2(x_coord, y_up_bottom)
						if y_down_bottom < best_y:
							best_y = y_down_bottom
							chosen_point = Vector2(x_coord, y_down_bottom)

				# 2) parte circular superior
				var top_center = Vector2(c.x, c.y - half_h)
				if abs(top_center.x - x_coord) <= r:
					var dy2 = sqrt(r*r - pow(x_coord - top_center.x, 2))
					var y_up_top = top_center.y - dy2
					var y_down_top = top_center.y + dy2
					if want_max_y:
						if y_down_top > best_y:
							best_y = y_down_top
							chosen_point = Vector2(x_coord, y_down_top)
						if y_up_top > best_y:
							best_y = y_up_top
							chosen_point = Vector2(x_coord, y_up_top)
					else:
						if y_up_top < best_y:
							best_y = y_up_top
							chosen_point = Vector2(x_coord, y_up_top)
						if y_down_top < best_y:
							best_y = y_down_top
							chosen_point = Vector2(x_coord, y_down_top)

	# Si no se encontró ninguna intersección, chosen_point sigue en Vector2.INF
	return chosen_point
	


## DEPRECATED
func get_rest_positions_anteior(container: Node2D, x_target: float) -> Array[Vector2]:
	var best_point:Vector2 = Vector2.INF
	var max_y:float = -INF
	
	var lowest_point:Vector2 = Vector2.INF    # Punto más abajo (Y más grande)
	var lowest_y:float = -INF
	var highest_point:Vector2 = Vector2.INF   # Punto más arriba (Y más pequeño)
	var highest_y:float = INF

	for child in container.get_children():
		# POLÍGONOS (CollisionPolygon2D o ConvexPolygonShape2D)
		if child is CollisionPolygon2D or (child is CollisionShape2D and child.shape is ConvexPolygonShape2D):
			var polygon:PackedVector2Array = child.polygon if child is CollisionPolygon2D else child.shape.points

			for i in range(polygon.size()):
				var global_p:Vector2 = child.global_transform * polygon[i]
				# Actualizar lowest/highest global
				if global_p.y > lowest_y:
					lowest_y = global_p.y
					lowest_point = global_p
				if global_p.y < highest_y:
					highest_y = global_p.y
					highest_point = global_p

			# Recorremos aristas para encontrar intersección en x_target
			for i in range(polygon.size()):
				var p1:Vector2 = child.global_transform * polygon[i]
				var p2:Vector2 = child.global_transform * polygon[(i + 1) % polygon.size()]

				if ((p1.x <= x_target and x_target <= p2.x) or (p2.x <= x_target and x_target <= p1.x)) and p1.x != p2.x:
					var intersection_y = p1.y + (p2.y - p1.y) * ((x_target - p1.x) / (p2.x - p1.x))
					if intersection_y > max_y:
						max_y = intersection_y
						best_point = Vector2(x_target, intersection_y)

		# RECTÁNGULOS, CÍRCULOS, CÁPSULAS... (similar lógica)
		elif child is CollisionShape2D:
			var xf:Transform2D = child.global_transform
			var shape:Shape2D = child.shape

			if shape is RectangleShape2D:
				var ext:Vector2 = shape.size * 0.5
				var local_points:Array[Vector2] = [
					Vector2(-ext.x, -ext.y),
					Vector2(ext.x, -ext.y),
					Vector2(ext.x,  ext.y),
					Vector2(-ext.x,  ext.y)
				]
				var global_points:Array[Vector2] = []
				for p in local_points:
					var g = xf * p
					global_points.append(g)
					# Actualizar lowest/highest global
					if g.y > lowest_y:
						lowest_y = g.y
						lowest_point = g
					if g.y < highest_y:
						highest_y = g.y
						highest_point = g

				# Buscar intersecciones con x_target
				for i in range(global_points.size()):
					var p1 = global_points[i]
					var p2 = global_points[(i + 1) % global_points.size()]
					if ((p1.x <= x_target and x_target <= p2.x) or (p2.x <= x_target and x_target <= p1.x)) and p1.x != p2.x:
						var intersection_y = p1.y + (p2.y - p1.y) * ((x_target - p1.x) / (p2.x - p1.x))
						if intersection_y > max_y:
							max_y = intersection_y
							best_point = Vector2(x_target, intersection_y)

			elif shape is CircleShape2D:
				var radius = shape.radius
				var center = xf.origin
				# Actualizar lowest/highest global del círculo (punto más bajo y más alto)
				var bottom = Vector2(center.x, center.y + radius)
				var top = Vector2(center.x, center.y - radius)
				if bottom.y > lowest_y:
					lowest_y = bottom.y
					lowest_point = bottom
				if top.y < highest_y:
					highest_y = top.y
					highest_point = top

				# Intersección con x_target
				if abs(center.x - x_target) <= radius:
					var dy = sqrt(radius * radius - pow(x_target - center.x, 2))
					var intersection_y = center.y + dy
					if intersection_y > max_y:
						max_y = intersection_y
						best_point = Vector2(x_target, intersection_y)

			elif shape is CapsuleShape2D:
				var radius:float = shape.radius
				var half_h:float = shape.height * 0.5
				var center:Vector2 = xf.origin
				# Aproximamos parte superior e inferior de la cápsula (sin considerar rotación completa)
				var bottom:Vector2 = Vector2(center.x, center.y + half_h + radius)
				var top:Vector2 = Vector2(center.x, center.y - half_h - radius)
				if bottom.y > lowest_y:
					lowest_y = bottom.y
					lowest_point = bottom
				if top.y < highest_y:
					highest_y = top.y
					highest_point = top

				# Intersección con x_target
				if abs(center.x - x_target) <= radius:
					var dy = sqrt(radius * radius - pow(x_target - center.x, 2))
					var intersection_y = center.y + half_h + dy
					if intersection_y > max_y:
						max_y = intersection_y
						best_point = Vector2(x_target, intersection_y)

	# Si no hubo intersección, best_point seguirá en Vector2.INF
	# Si no hubo nodos válidos, lowest_point y highest_point pueden ser Vector2.INF
	return [
		best_point if best_point != Vector2.INF else Vector2.INF,
		lowest_point if lowest_point != Vector2.INF else Vector2.INF,
		highest_point if highest_point != Vector2.INF else Vector2.INF
	]

## DEPRECATED
func test_rest(shape_data:ShapeData, cast_origin_global_position:Vector2, excluded_rids:Array[RID] = []):
	var query = PhysicsShapeQueryParameters2D.new()
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = collide_with_bodies
	query.collision_mask = collision_mask
	query.margin = collision_margin
	query.shape = shape_data.shape
	query.transform = shape_data.get_anchor_transform(cast_origin_global_position)
	query.exclude = excluded_rids #[area_to_place.get_rid()]
	
	# primero comprobamos si ya hay un overlap ya que las colisiones existentes se ignoran según la doc
	var data = space_state.get_rest_info(query)
	return data
	#if not data.is_empty():
		#if return_data == null: return_data = SweepingResult.new()
		#return_data.contact_point = data.point
		#return_data.shape_position = query.transform.origin
		#return_data.motion_pct = 0
		##prints("Existing overlap at start")
		#return return_data
	
