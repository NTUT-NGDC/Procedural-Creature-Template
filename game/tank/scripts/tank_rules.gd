class_name TankRules
extends RefCounted
## 生態缸的規則（像 Slither）：用頭的「前方」撞到別人（頭或身體都算，不管誰大），撞人的那隻就死掉，被撞的沒事。
## 「前方」是頭朝的方向左右各 ram_angle（平衡資料，預設 45 度）：頭的側面、後面擦到別人不算撞人。
## 兩隻都用前方碰到對方（正面對撞）就兩隻都死。
## 死掉的整隻散成一串大顆飼料，大家去搶。
## 都是不改任何東西的純函式：生態缸（裁判）每一幀拿每一對生物來問，之後連線的主機也用同一份。
## 係數（每級掉幾個飼料、重生無敵幾秒）在平衡資料 balance.tres 的「碰撞」。


## A 的頭有沒有碰到 B（B 的頭或身體任何一節，不管從哪個方向）
static func touches(a: Creature, b: Creature) -> bool:
	return _hit(a, b, PI)


## A 有沒有「撞到」B：A 的頭碰到 B，而且碰到的地方在 A 頭朝的方向左右各 ram_angle 以內（用臉撞的）
static func rams(a: Creature, b: Creature, balance: CreatureBalance) -> bool:
	return _hit(a, b, balance.ram_angle)


## A 的頭碰到 B 的哪一節（頭或身體），而且那一節在 A 前方左右各 angle 以內。
## 碰到一個圓最先碰到的點，就在「A 的頭 → 圓心」的方向上，所以看圓心的方向就好
static func _hit(a: Creature, b: Creature, angle: float) -> bool:
	var body: ChainBody = b.get_body()
	var points: PackedVector2Array = body.get_points() if body != null else PackedVector2Array([b.global_position])  # 每一節的位置
	var far: float = a.head_radius + (body.thickness * 1.5 if body != null else b.head_radius)  # 比最粗的地方還遠，就不用算這一節多粗
	for i: int in points.size():
		var distance: float = a.global_position.distance_to(points[i])
		if distance >= far or distance >= a.head_radius + (body.get_width(i) if body != null else b.head_radius):
			continue  # 沒碰到這一節
		if distance < 1.0 or absf(angle_difference(a.heading, a.global_position.angle_to_point(points[i]))) <= angle:
			return true  # 碰到了，而且在前方（疊在一起的時候也算）
	return false


## 鏡頭要拉到幾倍：視野是基本視野時 1（不拉遠），到上限時 max_zoom_out，中間照比例。眼睛越多看到的地圖越多
static func camera_zoom(sight: float, balance: CreatureBalance) -> float:
	var t: float = clampf(inverse_lerp(balance.base_sight, balance.max_sight, sight), 0.0, 1.0) if balance.max_sight > balance.base_sight else 0.0
	return lerpf(1.0, balance.max_zoom_out, t)


## 整隻生物（頭＋身體）佔的範圍：先用這個快速排除「離很遠、不可能碰到」的組合，再一節一節檢查
static func body_rect(creature: Creature) -> Rect2:
	var body: ChainBody = creature.get_body()
	var rect := Rect2(creature.global_position, Vector2.ZERO)
	if body == null:
		return rect.grow(creature.head_radius)
	for point: Vector2 in body.get_points():
		rect = rect.expand(point)
	return rect.grow(body.thickness + creature.head_radius)


## 復活、生出新生物時，spot 這個位置「還有多少空間」（像素）：離每隻生物的頭、身體多遠，取最近的。
## 生態缸（之後連線的主機）拿幾個隨機位置來比，挑空間最大的
static func spawn_room(spot: Vector2, creatures: Array[Creature]) -> float:
	var room: float = INF
	for other: Creature in creatures:
		room = minf(room, _distance_to_body(spot, other))
	return room


## spot 離這隻生物（頭＋身體）最近的地方多遠
static func _distance_to_body(spot: Vector2, creature: Creature) -> float:
	var nearest: float = spot.distance_to(creature.global_position)
	var body: ChainBody = creature.get_body()
	if body != null:
		for point: Vector2 in body.get_points():
			nearest = minf(nearest, spot.distance_to(point))
	return nearest


## 死掉的生物（等級 level）會掉幾個大顆飼料：（等級＋1）× 每級掉幾個，有上限
static func dropped_food(level: int, balance: CreatureBalance) -> int:
	return mini((level + 1) * balance.food_per_level, balance.max_drop_food)
