extends Node
## Web-only bridge between the in-page MediaPipe hand detector
## (export/web_head_include.html) and Godot. It registers a JavaScript callback
## that the detector invokes, and re-emits those events as Godot signals so
## scripts/main.gd can treat a webcam "frame" gesture exactly like a button press.
##
## No-op on every non-web platform: JavaScriptBridge has no browser to talk to.

signal frame_gesture_detected
signal camera_status_changed(status: String)  # "on" | "off" | "error"

# Kept as members so the JS callback isn't garbage-collected and the window
# interface stays available for request_camera().
var _cb
var _window

func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_window = JavaScriptBridge.get_interface("window")
	if _window == null:
		return
	_cb = JavaScriptBridge.create_callback(_on_js_event)
	_window.__godotGestureCb = _cb

## Asks the page to request camera access and start detection. Must be triggered
## from a real user gesture (e.g. clicking a screen open) or the browser blocks
## the prompt. Safe to call repeatedly — the page resumes a warm stream instantly.
func request_camera() -> void:
	if _window != null and _window.startGestureCamera:
		_window.startGestureCamera()

## Pauses detection when the player leaves a camera screen. The page keeps the
## webcam stream warm so the next request_camera() resumes without a delay.
func stop_camera() -> void:
	if _window != null and _window.stopGestureCamera:
		_window.stopGestureCamera()

func _on_js_event(args: Array) -> void:
	var msg := String(args[0])
	if msg == "photo":
		emit_signal("frame_gesture_detected")
	elif msg.begins_with("status:"):
		emit_signal("camera_status_changed", msg.substr(7))  # "on" | "off" | "error"
