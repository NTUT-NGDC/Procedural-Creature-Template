class_name TankRules
extends RefCounted
## 生態缸的規則（像 Slither）：頭撞到別人（頭或身體都算，不管誰大），撞人的那隻就死掉，被撞的沒事。
## 頭碰頭：誰衝向對方誰是撞人的（從側面撞過來的死）；兩隻都朝對方衝（正面對撞）就兩隻都死。
## 死掉的整隻散成一串大顆飼料，大家去搶。
## 都是不改任何東西的純函式：生態缸（裁判）每一幀拿每一對生物來問，之後連線的主機也用同一份。
## 係數（每級掉幾個飼料、重生無敵幾秒）在平衡資料 balance.tres 的「碰撞」。


## A 的頭有沒有撞到 B（B 的頭或身體任何一節）
static func touches(a: Creature, b: Creature) -> bool:
	var body: ChainBody = b.get_body()
	if body == null:  # 沒有身體：只有頭
		return a.global_position.distance_to(b.global_position) < a.head_radius + b.head_radius
	var points: PackedVector2Array = body.get_points()  # 每一節的位置
	var far: float = a.head_radius + body.thickness * 1.5  # 比最粗的地方還遠，就不用算這一節多粗
	for i: int in points.size():
		var distance: float = a.global_position.distance_to(points[i])
		if distance < far and distance < a.head_radius + body.get_width(i):
			return true
	return false


## 頭碰頭的時候，誰算撞人的：朝對方衝的速度（像素／秒）比較快的那隻；
## 兩隻都朝對方衝超過 head_on_speed（正面對撞），兩隻都算
static func head_on_rammers(a: Creature, b: Creature, balance: CreatureBalance) -> Array[Creature]:
	var a_in: float = a.velocity.dot(a.global_position.direction_to(b.global_position))  # A 朝 B 衝多快
	var b_in: float = b.velocity.dot(b.global_position.direction_to(a.global_position))  # B 朝 A 衝多快
	if a_in > balance.head_on_speed and b_in > balance.head_on_speed:
		return [a, b]
	return [a] if a_in >= b_in else [b]


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
