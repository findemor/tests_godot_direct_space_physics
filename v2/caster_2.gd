extends Polygon2D

@onready var a: Polygon2D = $"../A"
@onready var b: Polygon2D = $"../B"


@export var brick: Area2D
@export var step_speed:float = 10
@export var cast_length:Vector2 = Vector2(0, 2000)

var space_state: PhysicsDirectSpaceState2D  # Espacio de física

func _ready():
	space_state = get_world_2d().direct_space_state
	
	
	
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"):
		position = position + step_speed * Vector2.RIGHT
	if event.is_action_pressed("ui_left"):
		position = position + step_speed * Vector2.LEFT
	if event.is_action_pressed("ui_up"):
		brick.rotation_degrees += 10
		
func _physics_process(delta: float) -> void:
	if brick != null:
		swape(brick, global_position)

func get_shape(force_convex:bool) -> ConvexPolygonShape2D:
	var collision_polygon = brick.get_node_or_null("CollisionPolygon2D")
	if not collision_polygon:
		print("No se encontró CollisionPolygon2D en rigidbody_a")
		return

	# Convertir el polígono en una forma de colisión válida
	var polygon = collision_polygon.polygon
	if polygon.is_empty():
		print("El CollisionPolygon2D está vacío")
		return
	
	var shape_points:PackedVector2Array
	if not force_convex:
		shape_points = polygon
	else:
		## convertimos a convexo
		shape_points = Geometry2D.convex_hull(polygon)
		if shape_points.size() < 3:
			print("No se puede formar un polígono convexo con estos puntos")
			return null
		shape_points.resize(shape_points.size() - 1) ## duplica el ultimo pero shape no lo necesita
		
		
	var shape = ConvexPolygonShape2D.new()
	shape.points = shape_points #polygon  # Asigna los puntos del polígono
	
	##TODO para depurar visualmente
	$"../ConvexShadow".polygon = shape_points
	$"../ConvexShadow".global_transform = brick.global_transform
	
	return shape
	
	
	



#https://forum.godotengine.org/t/one-shot-shape-casts-in-2d/100355

## si fast_mode == true, es más rápido pero no devuelve información del punto de contacto ni de la colisión
func shape_sweep(query: PhysicsShapeQueryParameters2D, consider_existing_collision:bool = false, fast_mode:bool = true):
	const END_MOTION_CONTACT_GUARANTEE_MARGIN:float = 10 ## pixeles que se alarga el motion para asegurar el contacto
	
	var data = null
	var return_dictionary = {}
	
	if consider_existing_collision:
		# primero comprobamos si ya hay un overlap ya que las colisiones existentes se ignoran según la doc
		data = space_state.get_rest_info(query)
		if not data.is_empty():
			return_dictionary.contact_point = data.point
			return_dictionary.shape_position = query.transform.origin
			prints("Existing overlap at start")
			return return_dictionary
	
	## realizamos un cast_motion para ver cuanto se podría mover sin colisionar
	var motion = space_state.cast_motion(query)
	var start_pos = query.transform.get_origin()
	#var end_pos = start_pos + query.motion
	if motion[0] == 1:
		prints("No motion collision detected", motion)
		## WARNING para testeo
		$"../MotionUnsafe".visible = false
		$"../MotionSafe".visible = false
		
		return return_dictionary
	else:
		prints("Motion collision detected", motion)
		## calculamos las posiciones de contacto entre las que hay espacio libre
		#var unsafe_pos = start_pos + motion[1] * query.motion 
		var safe_pos = start_pos + motion[0] * query.motion 
		var end_contact_point : Vector2
		## estiramos un poco más el punto de contacto en la direccion del movimiento para garantizar que contactamos con lo que se ha detectado
		end_contact_point = start_pos + (motion[0] + END_MOTION_CONTACT_GUARANTEE_MARGIN / query.motion.length()) * query.motion
		
		
		## WARNING para testeo
		#$"../MotionUnsafe".visible = motion[1] != 1 ## o es cero cuando no hay contacto en este caso
		#$"../MotionUnsafe".position = unsafe_pos
		$"../MotionSafe".visible = true ## si hemos llegado hasta aqui es que hay contacto
		$"../MotionSafe".position = safe_pos
		
		
		return_dictionary.contact_point = end_contact_point
		return_dictionary.shape_position = safe_pos
		
		## si queremos que prevalezca esta comprobación, simplemente retornamos el contacto
		if fast_mode: 
			prints("Fast mode: proportion prevalency", motion)
			return return_dictionary
		
		## en otro caso, comprobamos como se acomoda en la posición de contacto que hemos detectado
		## ojo que esto depende del margen que le hayamos dado a END_MOTION_CONTACT_POINT_SAFE_PROPORTION
		query.transform = Transform2D(0, end_contact_point)
		query.motion = Vector2.ZERO
		data = space_state.get_rest_info(query)
		if data.is_empty():
			prints("No rest position found", motion)
			return return_dictionary
		else:
			return_dictionary.contact_point = data.point
			return_dictionary.shape_position = safe_pos
			prints("Rest position found")
			return return_dictionary
			
## detecta concave?
func intersection(at_global_pos:Vector2):
	# Crear una transformación basada en la original, pero con nueva posición
	var new_transform = brick.global_transform
	new_transform.origin = at_global_pos
	
	var query = PhysicsShapeQueryParameters2D.new()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1
	#query.shape = get_shape(false)
	## es concavo? preparamos el shape
	var collision_polygon = brick.get_node_or_null("CollisionPolygon2D")
	var shape = ConcavePolygonShape2D.new()
	## no se usa directamente el poligono sino pares de puntos
	var segments = PackedVector2Array()
	for i in range(collision_polygon.polygon.size()):
		var p1 =  collision_polygon.polygon[i]
		var p2 =  collision_polygon.polygon[(i + 1) %  collision_polygon.polygon.size()]  # Conectar el último con el primero
		segments.append(p1)
		segments.append(p2)
	shape.segments = segments
	
	query.shape = shape
	query.transform = new_transform
	query.exclude = [brick.get_rid()]
	
	var data = space_state.intersect_shape(query)
	prints("SHAPE COLLIDER DOWN ", null if data != null else data.collider)
			
			
func swape(area_to_place:Node2D, swaper_origin_global_position:Vector2):
	
	# Crear una transformación basada en la original, pero con nueva posición
	var new_transform = area_to_place.global_transform
	new_transform.origin = swaper_origin_global_position
	
	var query = PhysicsShapeQueryParameters2D.new()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1
	query.motion = cast_length
	query.shape = get_shape(true)
	query.transform = new_transform
	query.exclude = [area_to_place.get_rid()]
	
	var rd = shape_sweep(query, false, true)
	if rd.is_empty():
		print("    ->> no contact")
		a.visible = false
		b.visible = false
		area_to_place.visible = false
		
	else:
		var contact_point = rd["contact_point"]
		var empty_point = rd["shape_position"]
		prints("    ->> contact point: ", contact_point, empty_point)
		
		a.visible = true
		b.visible = true 
		a.position = empty_point
		b.position = contact_point + empty_point
		
		area_to_place.visible = true
		area_to_place.position = empty_point
		
		#intersection(global_position + Vector2.DOWN * 10)
