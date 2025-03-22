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
func scan_inside_hole(bottom_pos:Vector2, top_pos:Vector2):
	pass
	## conociendo la posición RELATIVA, respecto al centro, de los puntos clave (cada vez que se rota)
	## calculamos la diferencia de posición del centro respecto a la que tendria con el punto clave central en S (punto de soporte), que es cc (center_collision.x,lower_collision.y) del triple raycast
	## si en esa ubicación highest point está ocupado, es que no entra, podemos parar, no hay posibilidad de spawn.
	## en otro caso, elevamos la pieza:
	##    obtenemos todos los RID de las colisiones actuales en ese lugar
	##    cast_motion hacia arriba (distancia hasta que S == cc, o lo que es lo mismo, diferencia de longitud entre raycasts), excluyendo las colisiones actuales
	##    reubicando la estructura en ese punto de máximo desplazamiento, cast_motion hacia abajo, sin excluir colisiones. (lo dejamos caer desde ese "techo"). Activamos deteccion de colision en el inicio.
	##      si se pudo desplazar (o no hay colisión), ese es el punto de spawn. En otro caso asumimos que no habia espacio libre en el area porque sigue habiendo obstaculos.
	




	#
#func get_empty_space_for_point(point:Vector2, first_cast_length:float, search_direction:Vector2, search_step_cast_length:float, search_max_length:float) -> Array[Vector2]:
	#
	##var result:Array[Vector2] = [-Vector2.INF, Vector2.INF] # limite superior, limite inferior
	#var search_direction_bound:Vector2 = Vector2.INF
	#var support_direction_bound:Vector2 = Vector2.INF
	#
	#var query:PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.new()
	#query.collide_with_areas = collide_with_areas
	#query.collide_with_bodies = collide_with_bodies
	#query.collision_mask = collision_mask
	#
	#query.from = point
	#query.to = point + -1 * search_direction * first_cast_length # intentamos apoyarlo en la dirección contraria de la busqeuda (es decir, lo apoyamos en el suelo por debajo cuando estamos buscando hacia arriba)
	#var data:Dictionary = space_state.intersect_ray(query)
	#if not data.is_empty(): support_direction_bound = data.position ## hemos encontrado una posición de apoyo por debajo, nos vale
	#
	### si no hemos encontrado una posiciónd e apoyo, vamos moviendonos a pasos hacia arriba hast encontrarla
	#var search_origin:Vector2 = point + search_direction * search_step_cast_length
	#while support_direction_bound == Vector2.INF and search_origin.distance_to(point) <= search_max_length:
		#query.from = search_origin
		#query.to = point
		#data = space_state.intersect_ray(query)
		#if not data.is_empty(): support_direction_bound = data.position ## hemos encontrado una posición de apoyo por debajo, nos vale
	#
		### desplazamos el cursor de busqueda en la direccion especificada
		#search_origin += search_direction * search_step_cast_length
	#
	#if support_direction_bound != Vector2.INF:
		### si hemos encontrado una posicion de soporte, buscamos también la opuesta
		#query.from = support_direction_bound
		#query.to = support_direction_bound * -search_direction * search_max_length
	
		

## posiciones clave de la estructura
class StructureKeyPositions:
	var target_point_lowest:Vector2 #posición de punto más bajo de colisión de la estructura en x = x_target. Si no hay colisión, devuelve Vector2.INF
	var target_point_highest:Vector2 #poisión del punto más alto de colision de la estructrua en x = x_target. Si no hay colision devuelve Vector2.INF
	var lowest_point:Vector2 # posición del punto más bajo de la estructura formada por las formas. Es decir, aquel punto en el que la coordenada Y es mayor.
	var highest_point:Vector2 # posición del punto más alto de la estructura formada por las formas. Es decir, aquel punto en el que la coordenada Y es menor.
	var lowest_point_antipodal:Vector2 #Punto más alto (Y min.) en la misma X que el más bajo
	var highest_point_antipodal:Vector2 #, Punto más bajo (Y max.) en la misma X que el más alto


## Obtiene los puntos de apoyo más relevantes del nodo, analizando las formas que contiene
## container: nodo que contiene los nodos CollisionPolygon o CollisionShape que se analizarán
## x_target: posición en X en la que se obtendrá la posición de apoyo, es decir, el punto en el que, para esa X, hay un punto más bajo de colisión con cualquiera de las formas. Si no hay colisión, devuelve Vector2.INF
## Retorna un array con tres posiciones:
## [0]: best point, posición de punto más bajo de colisión en x = x_target. Si no hay colisión, devuelve Vector2.INF
## [1]: lowest_point, posición del punto más bajo de la estructura formada por las formas. Es decir, aquel punto en el que la coordenada Y es mayor.
## [2]: highest_point, posición del punto más alto de la estructura formada por las formas. Es decir, aquel punto en el que la coordenada Y es menor.
## [3]: top_in_lowest_x, Punto más alto (Y min.) en la misma X que el más bajo
## [4]: bottom_in_highest_x, Punto más bajo (Y max.) en la misma X que el más alto
func get_key_positions(container: Node2D, x_target: float) -> StructureKeyPositions:
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
	# "Punto más alto" en la misma X que el "más bajo" => buscamos intersección mín. Y
	# "Punto más bajo" en la misma X que el "más alto" => buscamos intersección máx. Y
	
	var key_positions_opposed:Array[Vector2] = VertexMath.get_key_positions_opposed_in_one_pass(container, highest_point.x, x_target, lowest_point.x)


	var key_positions:StructureKeyPositions = StructureKeyPositions.new()
	key_positions.target_point_lowest = key_positions_opposed[2]
	key_positions.target_point_highest = key_positions_opposed[1]
	key_positions.lowest_point = lowest_point
	key_positions.highest_point = highest_point
	key_positions.lowest_point_antipodal = key_positions_opposed[0]
	key_positions.highest_point_antipodal = key_positions_opposed[3]
	
	return key_positions



class VertexMath:

	# Devuelve un Array con estos tres puntos (Vector2) en orden:
	#  [bottom_in_x_highest, bottom_in_x_middle, top_in_x_lowest]
	#
	# Parámetros:
	# - container: Node2D que contiene CollisionPolygon2D o CollisionShape2D.
	# - x_highest: Coordenada X donde buscamos la intersección con Y mínima.
	# - x_middle:  Coordenada X donde buscamos la intersección con Y mínima.
	# - x_lowest:  Coordenada X donde buscamos la intersección con Y máxima.
	#
	# Retorna:
	# - Un Array con 3 Vector2. Si no hay intersección en alguno, retorna Vector2.INF en su lugar.
	static func get_key_positions_opposed_in_one_pass(container: Node2D, x_at_highest: float, x_middle: float, x_at_lowest: float) -> Array[Vector2]:
		var top_in_x_lowest := Vector2.INF
		var bottom_in_x_middle := Vector2.INF
		var bottom_in_x_highest := Vector2.INF
		var top_in_x_middle := Vector2.INF

		var best_top_lowest_y := -INF
		var best_bottom_middle_y := INF
		var best_bottom_highest_y := INF
		var best_top_middle_y := -INF

		for child in container.get_children():

			# --------------------------------------------------------------
			# 1) Polígonos (CollisionPolygon2D o CollisionShape2D con Convex)
			# --------------------------------------------------------------
			if child is CollisionPolygon2D or (child is CollisionShape2D and child.shape is ConvexPolygonShape2D):
				var polygon = child.polygon if child is CollisionPolygon2D else child.shape.points
				for i in range(polygon.size()):
					var p1 = child.global_transform * polygon[i]
					var p2 = child.global_transform * polygon[(i + 1) % polygon.size()]

					if p1.x != p2.x:
						# ---- x_at_highest, buscamos Y máxima ----
						if (p1.x <= x_at_highest and x_at_highest <= p2.x) or (p2.x <= x_at_highest and x_at_highest <= p1.x):
							var y_lowest = p1.y + (p2.y - p1.y) * ((x_at_highest - p1.x) / (p2.x - p1.x))
							if y_lowest > best_top_lowest_y:
								best_top_lowest_y = y_lowest
								top_in_x_lowest = Vector2(x_at_highest, y_lowest)

						# ---- x_middle, buscamos Y mínima ----
						if (p1.x <= x_middle and x_middle <= p2.x) or (p2.x <= x_middle and x_middle <= p1.x):
							var y_middle = p1.y + (p2.y - p1.y) * ((x_middle - p1.x) / (p2.x - p1.x))
							if y_middle < best_bottom_middle_y:
								best_bottom_middle_y = y_middle
								bottom_in_x_middle = Vector2(x_middle, y_middle)
						
						# ---- x_middle, buscamos Y máxima ----
						if (p1.x <= x_middle and x_middle <= p2.x) or (p2.x <= x_middle and x_middle <= p1.x):
							var y_middle = p1.y + (p2.y - p1.y) * ((x_middle - p1.x) / (p2.x - p1.x))
							if y_middle > best_top_middle_y:
								best_top_middle_y = y_middle
								top_in_x_middle = Vector2(x_middle, y_middle)

						# ---- x_at_lowest, buscamos Y mínima ----
						if (p1.x <= x_at_lowest and x_at_lowest <= p2.x) or (p2.x <= x_at_lowest and x_at_lowest <= p1.x):
							var y_highest = p1.y + (p2.y - p1.y) * ((x_at_lowest - p1.x) / (p2.x - p1.x))
							if y_highest < best_bottom_highest_y:
								best_bottom_highest_y = y_highest
								bottom_in_x_highest = Vector2(x_at_lowest, y_highest)

			# --------------------------------------------------------------
			# 2) CollisionShape2D específico: RECT, CÍRCULO, CÁPSULA, etc.
			# --------------------------------------------------------------
			elif child is CollisionShape2D:
				var xf = child.global_transform
				var shape = child.shape

				# -------------------- RECTÁNGULO --------------------
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
						if gp1.x != gp2.x:

							# x_at_highest
							if (gp1.x <= x_at_highest and x_at_highest <= gp2.x) or (gp2.x <= x_at_highest and x_at_highest <= gp1.x):
								var yL = gp1.y + (gp2.y - gp1.y) * ((x_at_highest - gp1.x) / (gp2.x - gp1.x))
								if yL > best_top_lowest_y:
									best_top_lowest_y = yL
									top_in_x_lowest = Vector2(x_at_highest, yL)

							# x_middle
							if (gp1.x <= x_middle and x_middle <= gp2.x) or (gp2.x <= x_middle and x_middle <= gp1.x):
								var yM = gp1.y + (gp2.y - gp1.y) * ((x_middle - gp1.x) / (gp2.x - gp1.x))
								if yM < best_bottom_middle_y:
									best_bottom_middle_y = yM
									bottom_in_x_middle = Vector2(x_middle, yM)
									
							# x_middle
							if (gp1.x <= x_middle and x_middle <= gp2.x) or (gp2.x <= x_middle and x_middle <= gp1.x):
								var yM = gp1.y + (gp2.y - gp1.y) * ((x_middle - gp1.x) / (gp2.x - gp1.x))
								if yM > best_bottom_middle_y:
									best_top_middle_y = yM
									top_in_x_middle = Vector2(x_middle, yM)

							# x_at_lowest
							if (gp1.x <= x_at_lowest and x_at_lowest <= gp2.x) or (gp2.x <= x_at_lowest and x_at_lowest <= gp1.x):
								var yH = gp1.y + (gp2.y - gp1.y) * ((x_at_lowest - gp1.x) / (gp2.x - gp1.x))
								if yH < best_bottom_highest_y:
									best_bottom_highest_y = yH
									bottom_in_x_highest = Vector2(x_at_lowest, yH)

				# -------------------- CÍRCULO --------------------
				elif shape is CircleShape2D:
					var r = shape.radius
					var c = xf.origin


					# x_at_highest (Y máx)
					var hits_l = check_circle_intersections(c, r, x_at_highest)
					if hits_l.size() > 0:
						if hits_l[1] > best_top_lowest_y:
							best_top_lowest_y = hits_l[1]
							top_in_x_lowest = Vector2(x_at_highest, hits_l[1])
						if hits_l[0] > best_top_lowest_y:
							best_top_lowest_y = hits_l[0]
							top_in_x_lowest = Vector2(x_at_highest, hits_l[0])

					# x_middle (Y mín)
					var hits_m = check_circle_intersections(c, r, x_middle)
					if hits_m.size() > 0:
						if hits_m[0] < best_bottom_middle_y:
							best_bottom_middle_y = hits_m[0]
							bottom_in_x_middle = Vector2(x_middle, hits_m[0])
						if hits_m[1] < best_bottom_middle_y:
							best_bottom_middle_y = hits_m[1]
							bottom_in_x_middle = Vector2(x_middle, hits_m[1])
						
						if hits_m[0] > best_top_middle_y:
							best_top_middle_y = hits_m[0]
							top_in_x_middle = Vector2(x_middle, hits_m[0])
						if hits_m[1] > best_top_middle_y:
							best_top_middle_y = hits_m[1]
							top_in_x_middle = Vector2(x_middle, hits_m[1])
							
					

					# x_at_lowest (Y mín)
					var hits_h = check_circle_intersections(c, r, x_at_lowest)
					if hits_h.size() > 0:
						if hits_h[0] < best_bottom_highest_y:
							best_bottom_highest_y = hits_h[0]
							bottom_in_x_highest = Vector2(x_at_lowest, hits_h[0])
						if hits_h[1] < best_bottom_highest_y:
							best_bottom_highest_y = hits_h[1]
							bottom_in_x_highest = Vector2(x_at_lowest, hits_h[1])

				# -------------------- CÁPSULA --------------------
				elif shape is CapsuleShape2D:
					var r_c = shape.radius
					var half_h = shape.height * 0.5
					var c_caps = xf.origin
					var bottom_center = Vector2(c_caps.x, c_caps.y + half_h)
					var top_center = Vector2(c_caps.x, c_caps.y - half_h)


					# x_at_highest => busco Y máx
					var y_lowest_caps = check_capsule_x(x_at_highest, r_c, bottom_center, top_center, true)
					if y_lowest_caps > best_top_lowest_y:
						best_top_lowest_y = y_lowest_caps
						top_in_x_lowest = Vector2(x_at_highest, y_lowest_caps)

					# x_middle => busco Y mín
					var y_middle_caps = check_capsule_x(x_middle, r_c, bottom_center, top_center, false)
					if y_middle_caps < best_bottom_middle_y:
						best_bottom_middle_y = y_middle_caps
						bottom_in_x_middle = Vector2(x_middle, y_middle_caps)
						
					var y_middle_caps_bot = check_capsule_x(x_middle, r_c, bottom_center, top_center, true)
					if y_middle_caps_bot > best_top_middle_y:
						best_top_middle_y = y_middle_caps_bot
						top_in_x_middle = Vector2(x_middle, y_middle_caps_bot)

					# x_at_lowest => busco Y mín
					var y_highest_caps = check_capsule_x(x_at_lowest, r_c, bottom_center, top_center, false)
					if y_highest_caps < best_bottom_highest_y:
						best_bottom_highest_y = y_highest_caps
						bottom_in_x_highest = Vector2(x_at_lowest, y_highest_caps)

		return [bottom_in_x_highest, bottom_in_x_middle, top_in_x_middle, top_in_x_lowest]

	static func check_circle_intersections(c:Vector2, r:float, x_value: float) -> Array[float]:
		# Devuelve la intersección más alta y más baja como Array [y_up, y_down], o null si no hay
		if abs(c.x - x_value) <= r:
			var dy = sqrt(r * r - pow(x_value - c.x, 2))
			return [c.y - dy, c.y + dy]
		return []

	static func capsule_circle_check(x_value: float, center: Vector2, r_c:float) -> Array:
		if abs(center.x - x_value) <= r_c:
			var dy = sqrt(r_c * r_c - pow(x_value - center.x, 2))
			return [center.y - dy, center.y + dy]
		return []

	static func check_capsule_x(x_value: float, r_c:float, bottom_center:Vector2, top_center:Vector2, is_for_max: bool) -> float:
		# Retorna la mejor intersección (máx o mín) en base a las dos "cúpulas"
		var b_hits = capsule_circle_check(x_value, bottom_center, r_c)
		var t_hits = capsule_circle_check(x_value, top_center, r_c)
		var candidates = []
		if b_hits:
			candidates.append(b_hits[0])
			candidates.append(b_hits[1])
		if t_hits:
			candidates.append(t_hits[0])
			candidates.append(t_hits[1])
		if candidates.size() == 0:
			return -INF if is_for_max else INF
		return max(candidates) if is_for_max else min(candidates)
