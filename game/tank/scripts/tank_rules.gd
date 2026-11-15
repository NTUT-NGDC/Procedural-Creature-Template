class_name TankRules
extends RefCounted
## 生態缸的規則：誰吃得掉誰、撞到身體扣幾級、掉幾個飼料。
## 都是不改任何東西的純函式：生態缸（裁判）每一幀拿每一對生物來問，之後連線的主機也用同一份。
## 係數（倍數、頭佔幾成、每級掉幾個飼料）在平衡資料 balance.tres 的「大吃小」。

## 兩隻生物碰到的方式
enum Contact { NONE, HEAD, BODY }


## A 吃不吃得掉 B：A 的體型至少是 B 的 eat_ratio 倍
static func can_eat(a: Creature, b: Creature, balance: CreatureBalance) -> bool:
	var a_stats: CreatureStats = a.get_stats()
	var b_stats: CreatureStats = b.get_stats()
	if a_stats == null or b_stats == null:
		return false
	return a_stats.size >= b_stats.size * balance.eat_ratio


## A 的頭碰到 B 的哪裡：B 的「頭」（身體的前 head_zone 成）、B 的身體、或沒碰到
static func contact(a: Creature, b: Creature, balance: CreatureBalance) -> Contact:
	var body: ChainBody = b.get_body()
	if body == null:  # 沒有身體：只有頭
		return Contact.HEAD if a.global_position.distance_to(b.global_position) < a.head_radius + b.head_radius else Contact.NONE
	var points: PackedVector2Array = body.get_points()  # 每一節的位置
	var head_joints: int = maxi(ceili(points.size() * balance.head_zone), 1)
	var far: float = a.head_radius + body.thickness * 1.5  # 比最粗的地方還遠，就不用算這一節多粗
	for i: int in points.size():  # 從頭往尾巴找，先碰到頭就算咬頭
		var distance: float = a.global_position.distance_to(points[i])
		if distance < far and distance < a.head_radius + body.get_width(i):
			return Contact.HEAD if i < head_joints else Contact.BODY
	return Contact.NONE


## 整隻生物（頭＋身體）佔的範圍：先用這個快速排除「離很遠、不可能碰到」的組合，再一節一節檢查
static func body_rect(creature: Creature) -> Rect2:
	var body: ChainBody = creature.get_body()
	var rect := Rect2(creature.global_position, Vector2.ZERO)
	if body == null:
		return rect.grow(creature.head_radius)
	for point: Vector2 in body.get_points():
		rect = rect.expand(point)
	return rect.grow(body.thickness + creature.head_radius)


## 復活、生出新生物時，spot 這個位置「還有多少空間」（像素）：離每隻生物的身體多遠，取最近的。
## 吃得掉我（體型 size）的生物，還要扣掉牠的視野：正的＝不在任何吃得掉我的生物的視野裡。
## 生態缸（之後連線的主機）拿幾個隨機位置來比，挑空間最大的
static func spawn_room(spot: Vector2, size: float, creatures: Array[Creature], balance: CreatureBalance) -> float:
	var room: float = INF
	for other: Creature in creatures:
		var distance: float = _distance_to_body(spot, other)
		var stats: CreatureStats = other.get_stats()
		if stats != null and stats.size >= size * balance.eat_ratio:
			distance -= stats.sight  # 吃得掉我的：要離開牠的視野才算安全
		room = minf(room, distance)
	return room


## spot 離這隻生物（頭＋身體）最近的地方多遠
static func _distance_to_body(spot: Vector2, creature: Creature) -> float:
	var nearest: float = spot.distance_to(creature.global_position)
	var body: ChainBody = creature.get_body()
	if body != null:
		for point: Vector2 in body.get_points():
			nearest = minf(nearest, spot.distance_to(point))
	return nearest


## 撞到別人身體要扣幾級：對方的等級，對方 0 級也扣 1 級
static func hit_damage(victim_level: int) -> int:
	return maxi(victim_level, 1)


## 掉了 levels 級（被吃掉的是等級＋1），會掉幾個飼料
static func dropped_food(levels: int, balance: CreatureBalance) -> int:
	return mini(levels * balance.food_per_level, balance.max_drop_food)
