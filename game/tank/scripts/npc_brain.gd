class_name NpcBrain
extends RefCounted
## NPC 的大腦：每一幀決定要往哪裡游。照順序問三個問題，第一個成立的就照做：
##   1. 附近有吃得掉我的？→ 逃（很近就加速）
##   2. 看得到我吃得掉的？→ 追牠的頭（快追到就加速）
##   3. 看得到飼料？→ 去吃
##   都沒有 → 回傳空的字典，生物自己漫遊
## 不管往哪游，都會避開別人的身體（撞到會掉級）和地圖邊緣。
## 「看得到」＝在視野（能力裡的 sight）裡面，所以眼睛多的 NPC 比較會逃、比較會追。

## 敵人在視野的幾成以內才逃（太遠的不理）
const FLEE_RANGE: float = 0.6
## 敵人、獵物在視野的幾成以內就加速
const BOOST_RANGE: float = 0.35
## 別人的身體在「頭的半徑幾倍」以內就要避開
const AVOID_RANGE: float = 3.0
## 離地圖邊緣幾像素以內就往裡面轉
const WALL_MARGIN: float = 120.0


## 決定這一幀要往哪走：{"angle": 弧度, "speed": 像素／秒, "boost": 要不要加速}，什麼都沒看到是空的
static func choose_target(me: Creature, creatures: Array[Creature], foods: Array[Node]) -> Dictionary:
	var sight: float = me.get_stats().sight
	var balance: CreatureBalance = me.get_balance()
	# 1. 逃：最近的、吃得掉我的
	var threat: Creature = _nearest(me, creatures, sight * FLEE_RANGE, func(other: Creature) -> bool: return TankRules.can_eat(other, me, balance))
	if threat != null:
		return _go(me, me.global_position - threat.global_position, creatures, _close(me, threat, sight))
	# 2. 追：最近的、我吃得掉的，對準牠的頭
	var prey: Creature = _nearest(me, creatures, sight, func(other: Creature) -> bool: return TankRules.can_eat(me, other, balance))
	if prey != null:
		return _go(me, prey.global_position - me.global_position, creatures, _close(me, prey, sight))
	# 3. 吃飼料：最近的
	var food: Node2D = null
	for item: Node in foods:
		var node: Node2D = item as Node2D
		if node != null and node.is_in_group("food") and me.global_position.distance_to(node.global_position) < sight:
			if food == null or me.global_position.distance_to(node.global_position) < me.global_position.distance_to(food.global_position):
				food = node
	if food != null:
		return _go(me, food.global_position - me.global_position, creatures, false)
	return {}


## 往 direction 游，再加上「避開別人的身體」「避開邊緣」
static func _go(me: Creature, direction: Vector2, creatures: Array[Creature], boost: bool) -> Dictionary:
	var steer: Vector2 = direction.normalized() + avoid_bodies(me, creatures) + _avoid_walls(me)
	return {"angle": steer.angle() if steer != Vector2.ZERO else me.heading, "speed": me.speed, "boost": boost}


## 避開別人的身體（頭不用避，咬頭是吃）：每一節把我往外推，離得越近推越大力
static func avoid_bodies(me: Creature, creatures: Array[Creature]) -> Vector2:
	var push := Vector2.ZERO
	for other: Creature in creatures:
		var body: ChainBody = other.get_body()
		if other == me or body == null:
			continue
		if me.global_position.distance_to(other.global_position) > body.joint_count() * body.spacing + me.head_radius * AVOID_RANGE + body.thickness:
			continue  # 整隻都離很遠：跳過，不用一節一節算
		var points: PackedVector2Array = body.get_points()  # 每一節的位置
		var head_joints: int = maxi(ceili(points.size() * me.get_balance().head_zone), 1)
		var far: float = me.head_radius * AVOID_RANGE + body.thickness * 1.5  # 比最粗的地方還遠，就不用算這一節多粗
		for i: int in range(head_joints, points.size()):
			var offset: Vector2 = me.global_position - points[i]
			if offset.length() > far:
				continue
			var reach: float = me.head_radius * AVOID_RANGE + body.get_width(i)
			if offset != Vector2.ZERO and offset.length() < reach:
				push += offset.normalized() * (1.0 - offset.length() / reach) * 2.0
	return push


## 太靠近地圖邊緣：往裡面推
static func _avoid_walls(me: Creature) -> Vector2:
	var inside: Rect2 = me.get_bounds().grow(-WALL_MARGIN)
	if inside.has_point(me.global_position):
		return Vector2.ZERO
	return (inside.get_center() - me.global_position).normalized()


## 範圍 reach 以內、符合條件（wanted）的生物裡，最近的那隻
static func _nearest(me: Creature, creatures: Array[Creature], reach: float, wanted: Callable) -> Creature:
	var nearest: Creature = null
	for other: Creature in creatures:
		if other == me or other.is_invincible() or me.global_position.distance_to(other.global_position) > reach:
			continue
		if not wanted.call(other):
			continue
		if nearest == null or me.global_position.distance_to(other.global_position) < me.global_position.distance_to(nearest.global_position):
			nearest = other
	return nearest


## 夠近了就加速
static func _close(me: Creature, other: Creature, sight: float) -> bool:
	return me.global_position.distance_to(other.global_position) < sight * BOOST_RANGE
