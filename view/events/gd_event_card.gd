extends PanelContainer
## VIEW: one event card in the events sheet.
##
## Bound from an EventRow value object rather than a live ViewModel, the same way
## a growth row is: the sheet is spawned on open and freed on close, and the queue
## is rebuilt whole whenever it changes, so the card re-binds a fresh snapshot on
## every refresh instead of holding a subscription of its own.
##
## One scene with three mutually exclusive bodies. A card is a boon, a quest or a
## countdown for its whole life - the kind is fixed by the def - so the bodies are
## shown and hidden rather than being three scenes the sheet has to choose between.

## The card owns no state, so presses are passed up rather than acted on here.
signal collect_requested(instance_id: int)
signal fulfil_requested(instance_id: int)
signal skip_requested(instance_id: int)

@export var color_rail: ColorRect
@export var color_dot: ColorRect
@export var lbl_eyebrow: Label
@export var btn_skip: Button
@export var lbl_title: Label
@export var lbl_description: Label

@export var btn_collect: Button
@export var box_spend: HBoxContainer
@export var lbl_spend: Label
@export var lbl_spend_reward: Label
@export var btn_fulfil: Button
@export var box_progress: VBoxContainer
@export var lbl_progress: Label
@export var lbl_progress_reward: Label
@export var bar_progress: ProgressBar

var _instance_id: int

func _ready() -> void:
	btn_collect.pressed.connect(_on_collect_pressed)
	btn_fulfil.pressed.connect(_on_fulfil_pressed)
	btn_skip.pressed.connect(_on_skip_pressed)

func bind(row: EventRow) -> void:
	_instance_id = row.instance_id
	color_rail.color = row.accent
	color_dot.color = row.accent
	lbl_eyebrow.add_theme_color_override(&"font_color", row.accent)
	lbl_title.text = row.title
	lbl_description.text = row.description

	btn_collect.visible = row.kind == RandomEventDef.Kind.BOON
	box_spend.visible = row.kind == RandomEventDef.Kind.SPEND
	box_progress.visible = row.kind == RandomEventDef.Kind.PROGRESS

	btn_collect.text = row.action_text
	lbl_spend.text = row.action_text
	lbl_spend_reward.text = "-> %s" % row.reward_text
	# Kept visible but disabled rather than hidden, so the card doesn't change
	# height the moment the balance dips below the ask.
	btn_fulfil.disabled = not row.enabled
	lbl_progress.text = row.progress_text
	lbl_progress_reward.text = row.reward_text
	bar_progress.value = row.progress_pct * 100.0

func _on_collect_pressed() -> void:
	collect_requested.emit(_instance_id)

func _on_fulfil_pressed() -> void:
	fulfil_requested.emit(_instance_id)

func _on_skip_pressed() -> void:
	skip_requested.emit(_instance_id)
